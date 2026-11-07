# Troubleshooting

Start with the read-only health check:

```bash
scripts/check-cameras.sh
```

## The webcam stopped working after an update

**Kernel update.** DKMS rebuilds `hm1092-dell` (and `ipu6-isys-pmguard` on the 9340) automatically if
the kernel headers metapackage is installed (`linux-headers-generic` or the HWE variant). If a new
kernel changes an internal interface, the build can fail — then the HM1092 driver is missing and the
**RGB webcam breaks too** (see [how-it-works](how-it-works.md#problem-1--the-webcam-is-missing-entirely-kernel)).

1. At boot hold **Shift** (or tap **Esc**) → *Advanced options for Ubuntu* → pick the previous kernel.
2. `dkms status` shows which module failed to build for the new kernel.

**Any update that rebuilt the initramfs.** Look for

```
intel-ipu6 0000:00:05.0: Direct firmware load for intel/ipu/ipu6epmtl_fw.bin failed with error -2
```

(`ipu7_fw.bin` on the 9350). Install the dracut omit file from `config/<model>/dracut/` and run
`sudo update-initramfs -u`. Verify: `sudo lsinitrd /boot/initrd.img-$(uname -r) | grep -iE 'ipu[67]|ov02c10|hm1092'`
should print nothing (an `inside-secure/.../ipue.bin` match is unrelated).

## The laptop crashes or hangs while booting after installing a driver

Boot with the module blacklisted: GRUB menu (hold **Shift** / tap **Esc**) → **e** on the Ubuntu
entry → append `modprobe.blacklist=hm1092` to the line starting with `linux` → **Ctrl+X**. Then remove
the DKMS package (`sudo dkms remove hm1092-dell/1.1 --all`).

## Never reload the camera sensor drivers live

`modprobe -r ov02c10 && modprobe ov02c10` panicked kernel 7.3 on the 9340 (use-after-free while
re-reading the bridge's software node). Apply all driver changes with a **reboot**. Various forum posts
suggest reloading the sensor module as a workaround — don't.

## Apps see no camera / only "ipu6"/"ipu7" entries

- `wpctl status` → *Video → Sources* should show "Front Camera" and "IR Camera".
- If empty, check WirePlumber's log for `Permission denied` on `/dev/media0`:
  `journalctl --user -b -u wireplumber | grep -i media0` → install `wait-for-camera.conf`, or just run
  `systemctl --user restart wireplumber`.
- Zoom and other raw-V4L2 apps: use the **Virtual Camera** (v4l2-relayd setup).

## Sound devices AND cameras disappeared (only "Dummy Output")

A WirePlumber rule using `device.disabled` has stalled WirePlumber (bug in 0.5.17, see
[how-it-works](how-it-works.md#problem-4--apps-see-30-48-useless-ipu6ipu7-cameras-or-none-desktop)).
Find it with `grep -rn 'device.disabled' ~/.config/wireplumber /etc/wireplumber /usr/share/wireplumber/wireplumber.conf.d`,
change it to `node.disabled` (or remove the file), then `systemctl --user restart wireplumber`.
Avoid restarting WirePlumber repeatedly while debugging — it also owns your audio devices; a reboot
resets everything cleanly.

## GNOME Camera: "could not play video stream"

It picked "Virtual Camera (V4L2)". Make sure the loopback hide rule is active
(`wpctl status` should list only "Front Camera" and "IR Camera" under Video → Sources).

## Google Meet / Chrome: blank page

`scripts/grant-chrome-camera.sh`, then fully quit and restart Chrome. Chrome must have
*PipeWire Camera support* enabled in `chrome://flags`. Choose "Front Camera" in Meet's video settings.

## Zoom shows "Virtual Camera" but nothing works / the relay seems dead

- `systemctl status 'v4l2-relayd@*'` — no instance means `/etc/v4l2-relayd.d/webcam.conf` is missing.
- `ps -o args= -C v4l2-relayd` must show `camera-name=\\_SB_.LNK1` (two backslashes) — see the
  backslash note in [how-it-works](how-it-works.md#problem-6--zoom-only-shows-ipu7-v4l2-only-apps).
- The stock relay binary stalls after a few frames; the patched one is required.
- If it delivers only a frame or two after another app used the camera, restart it:
  `sudo systemctl restart v4l2-relayd@xps13-webcam` (seen once; not reproducible yet).
- Only one app can use the RGB camera at a time: a Meet call, Cheese or Gaze's RGB scan will make
  the Virtual Camera unavailable while they run, and vice versa.

## Gaze

- `gaze doctor` first.
- `encrypt_templates` is on by default and **needs a TPM** — gazed exits with status 77 if the TPM is
  disabled in the BIOS (Dell: F2 → Security). Either enable it or set `encrypt_templates = false`.
- Don't pick "Primary camera" in the Gaze GUI — it selects the IR camera on these laptops.
- Lock screen / GDM need the Gaze GNOME extension enabled (see [how-it-works](how-it-works.md#problem-7--gaze-face-authentication-cant-use-these-cameras)).
- Debug the daemon: add `Environment=RUST_LOG=info,gaze_vision=debug,gazed=debug` in a drop-in for
  `gazed.service`, restart, and read `journalctl -u gazed`.

## Harmless log messages

- `ov02c10 ...: Unable to get rectangle N on pad 0/0` / `The sensor kernel driver needs to be fixed` —
  libcamera noting optional sensor-driver features.
- `deferred probe pending: intel-ipu6: IPU6 bridge init failed` — waits for IVSC, then succeeds.
- `csi2-4 error: Frame sync error` once per stream stop (IPU6).
- `hm1092: module verification failed` — DKMS module with Secure Boot off.
- `(systemd) PAM unable to dlopen(pam_gaze.so): undefined symbol: pam_set_data` — `systemd --user`
  loading `common-auth`; harmless.
