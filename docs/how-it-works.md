# How it works — and why each fix exists

## The camera hardware

Both laptops have two sensors on MIPI CSI-2, driven by Intel's camera unit (IPU6 on the 9340,
IPU7 on the 9350):

| | RGB webcam | IR camera |
|---|---|---|
| Sensor | OmniVision OV02C10 (ACPI `OVTI02C1`) | Himax HM1092 (ACPI `HIMX1092`), mono near-IR, 640×368 usable |
| Kernel driver | `ov02c10` (in-kernel) | **none in-kernel** → `dkms/hm1092-dell` |
| Bridge | Intel IVSC (9340) / Intel CVS (9350) sits in front of the sensor | direct to a CSI-2 port |
| Control bus | I2C via a USB bridge: LJCA (9340) / Lattice "usbio" (9350) | same |
| Power control | ACPI `INT3472` "discrete" device `DSC0`: 19.2 MHz clock, power rails, IR LED | same `DSC0` |

The IPU's raw capture nodes (`/dev/video*`, driver `isys`, card name `ipu6` / `ipu7`) output
unprocessed Bayer data and only work after **libcamera** has configured the pipeline. libcamera's
software ISP turns them into usable images.

## Problem 1 — the webcam is missing entirely (kernel)

The IPU capture driver (`ipu6-isys.c` / `ipu7-isys.c`) creates `/dev/v4l-subdev` nodes for sensors in
two places: when a sensor binds *directly* to it, and in the async notifier's **`complete`** callback,
which only runs once **every sensor listed in ACPI** has bound.

The OV02C10 binds *through* the IVSC/CVS bridge, so its node can only come from `complete`. And
`complete` never runs, because the HM1092 has no driver. Check it yourself:

```
$ sudo cat /sys/kernel/debug/v4l2-async/pending_async_subdevices
ipu7:
 [fwnode] dev=i2c-HIMX1092:00, node=HIMX1092-1/port@0/endpoint@0     <- the blocker
```

Two possible fixes:
- **Give the HM1092 a driver** (`dkms/hm1092-dell`) — fixes both cameras. ✅ used on both models.
- **Make the bridge ignore the HM1092** (`dkms/ipu-bridge-noir`) — RGB only. Kept as a fallback.

### The HM1092 driver

The driver is Jake Steinman's July 2026 submission to linux-media (developed on an IPU7 Dell XPS 16
behind a Synaptics vision bridge). Two other things mattered:

- **Clock / link frequency.** Dell boards feed the sensor a **19.2 MHz** clock; Steinman's
  Dell-derived register table gives a **180.48 MHz** link, which matches. (A competing series derived
  from ASUS files assumes 24 MHz and would run the link at the wrong rate here.)
- **Reset line (9340).** On the 9340, `DSC0` exposes the sensor's **reset GPIO** (INT3472 type `0x00`).
  The original driver never released it, so the chip-ID read failed. → `patches/0001-reset-gpio.patch`.
  On the 9350 there is no reset GPIO; instead a **HANDSHAKE** GPIO (type `0x12`) becomes a `dvdd`
  regulator with a 200 ms enable delay that asks the Lattice chip to hand the sensor to the host.
  The driver already requests `dvdd`, so no change was needed.
- **IR illuminator.** INT3472 registers the IR flood LED as an LED class device
  (`HIMX1092_00::ir_flood_led`) with a lookup for con_id `ir_flood`. The original driver only looked
  for a raw `ir-led` GPIO, so the LED never lit. → `patches/0002-ir-flood-led.patch` turns it on for
  exactly as long as the IR camera streams.

## Problem 2 — boot-time crash (9340 / IPU6 only)

`isys_runtime_pm_suspend()` could run during `isys_probe()` before the driver data was set,
dereferencing NULL (`isys+0x31c`) and panicking about one boot in a few. → `dkms/ipu6-isys-pmguard`
returns `-EBUSY` in that window. IPU7's driver already has this guard.

## Problem 3 — webcam dies after a routine update (both)

Ubuntu 26.10 builds the initramfs with **dracut in host-only mode**, which copies the drivers of the
hardware in use. `intel_ipu6` / `intel_ipu7` load their firmware (`ipu6epmtl_fw.bin` / `ipu7_fw.bin`)
**without declaring it** (`modinfo -F firmware` is empty), so dracut copies the driver but not the
firmware. The next boot starts the IPU from the initramfs, the firmware load fails with `-ENOENT`,
and both cameras are gone. → `config/<model>/dracut/90-camera-not-in-initramfs.conf` keeps all camera
drivers out of the initramfs so they load from the root filesystem.

## Problem 4 — apps see 30-48 useless "ipu6/ipu7" cameras, or none (desktop)

- PipeWire's V4L2 monitor exposes every raw `isys` node as a camera. → `50-hide-ipu-raw.conf`.
- WirePlumber starts at login before the user's ACL on `/dev/media0` is applied; libcamera gets
  `EACCES` and never retries, so the real cameras never appear. → `wait-for-camera.conf`.
- Both libcamera cameras are called "Built-in Front Camera" and the IR one became the default.
  → `51-camera-names.conf` ("Front Camera" default, "IR Camera").
- **Hide with `node.disabled`, never `device.disabled`.** In WirePlumber 0.5.17,
  `scripts/monitors/v4l2/create-device.lua` is an asynchronous hook whose `device.disabled` branch
  returns without calling `transition:advance()`. The event queue then waits forever, and every device
  created after it never appears — the libcamera cameras *and the ALSA speakers/microphones*. Whether a
  device rule matches at that stage depends on boot timing (e.g. the v4l2loopback device with
  `exclusive_caps`), so a `device.disabled` rule can work for days and then break sound and cameras.
  The `node.disabled` path in `create-node.lua` advances correctly.
- The relay's "Virtual Camera" must be hidden from PipeWire too: GNOME Camera opens the first non-IR
  camera, and the loopback node offers only one fixed format it cannot negotiate
  ("could not play video stream").

## Problem 5 — Chrome / Google Meet hangs (both)

Chrome's PipeWire camera path goes through the xdg-desktop-portal. For the unsandboxed .deb Chrome,
GNOME refuses to show the access dialog ("Only the focused app is allowed to show a system access
dialog") and the portal treats that as **deny**; Meet hangs on a blank page.
→ `scripts/grant-chrome-camera.sh` pre-stores the permission. (Pixel formats are fine: Chrome accepts
the RGBA/BGRA formats libcamera offers.) Chrome lists the IR camera first — pick "Front Camera".

## Problem 6 — Zoom only shows "ipu7" (V4L2-only apps)

Zoom (snap) opens `/dev/video*` directly and has no PipeWire/libcamera support. → a **virtual
webcam**: `v4l2loopback` (shipped with Ubuntu kernels) fed by **v4l2-relayd**, which starts the real
camera only while an app has the virtual one open. Stock v4l2-relayd 0.2.0 did not work here:

1. instances come only from `/etc/v4l2-relayd.d/*.conf`;
2. the camera name `\_SB_.LNK1` needs **8** backslashes in that file (systemd, the unit's `sh -c`, and
   GStreamer syntax each halve them);
3. caps filters inside the pipeline strings don't parse in the relay — use caps-free pipelines;
4. without a splash source the loopback isn't streaming when a client opens it → hang;
5. even then it stalls after ~16 frames: the relay gives its input pipeline the output pipeline's
   base time, sources stamp buffers on their own timeline, and `v4l2sink` drops every frame as late.
   → `patches/v4l2-relayd/` disables appsink clock sync and re-stamps buffers on hand-over.
6. **No `videorate` in the input pipeline.** It decides which frames to pass purely from timestamps;
   `libcamerasrc` timestamps drift away from the relay's clock, so with `videorate` the relay delivered
   full frame rate for ~5 minutes on the 9350 and then ~40/90 frames, and on the 9340 (IPU6) almost
   none from the start. libcamera already delivers the 30 fps the relay asks for.

## Problem 7 — Gaze face authentication can't use these cameras

Gaze's privileged daemon only trusts real `/dev/video*` nodes (anti-injection design), plus a
libcamera fallback for the RGB `"primary"` setting that picks the *first* libcamera camera — the IR
one here. → `patches/gaze/`:

1. `libcamera:<name>` camera sources, opened by the daemon's own libcamera (same trust as Gaze's
   fallback);
2. the GUI's `pipewiresrc target-object=libcamera_input.<id>` choices are mapped back to the
   libcamera camera (reversing WirePlumber's name sanitising) — PipeWire is never read from;
3. the appsink must not clock-sync for `libcamerasrc` (same timestamp issue as in v4l2-relayd: one
   black frame, then nothing). This also affects stock Gaze's IPU6/IPU7 fallback.

On GNOME, Gaze 0.4.2's PAM module deliberately ignores every `gdm-*` service except `gdm-face`, so the
**lock screen and login screen need the Gaze GNOME extension** — `pam-auth-update` alone only covers
`sudo` and polkit.
