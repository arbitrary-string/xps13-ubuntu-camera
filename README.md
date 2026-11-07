# Dell XPS 13 webcam + IR camera on Ubuntu (IPU6 / IPU7)

Fixes, drivers and configuration to get **both built-in cameras** — the RGB webcam and the
Windows-Hello-style IR camera — working on Ubuntu, for:

| Model | CPU / camera unit | RGB sensor | IR sensor | Bridge chip | Status |
|---|---|---|---|---|---|
| **XPS 13 9340** | Meteor Lake / **IPU6** (`8086:7d19`) | OV02C10 | Himax HM1092 | Intel IVSC + LJCA USB-I2C | ✅ both cameras, Gaze |
| **XPS 13 9350** | Lunar Lake / **IPU7** (`8086:645d`) | OV02C10 | Himax HM1092 | Lattice "AI USB" (`2ac1:20c9`) / Intel CVS + usbio | ✅ both cameras, Gaze, Chrome/Meet, Zoom |

Tested on **Ubuntu 26.10** with kernel **7.3.0-10-generic**, libcamera 0.7.0, PipeWire/WirePlumber 0.5,
Gaze 0.4.2. Other kernels and releases may need adjustments — see [docs/troubleshooting.md](docs/troubleshooting.md).

> **Status: personal hardware-enablement work, not an official package.** Everything here was
> developed and verified on one machine of each model. It touches kernel modules, the boot image and
> system services. Read what each step does before running it, keep your password login working,
> and know how to boot an older kernel from GRUB. An installer/package is planned.

## Why the webcam doesn't work out of the box

On both models the stock kernel *has* the RGB sensor driver (`ov02c10`), yet the webcam is dead:

1. The camera firmware tables list **two** sensors: the RGB OV02C10 and the IR **HM1092**.
2. The kernel has **no HM1092 driver**, so the IR sensor never binds.
3. The IPU capture driver only creates the sensors' control devices once *every* listed sensor is
   bound — so the OV02C10 behind the IVSC/CVS bridge never gets its `/dev/v4l-subdev` node, and
   libcamera cannot use the webcam either.

Adding an HM1092 driver fixes both cameras at once. After that, a handful of userspace problems
(PipeWire, browsers, Zoom, face login) each needed their own fix. Full explanation:
[docs/how-it-works.md](docs/how-it-works.md).

## What's in here

| Path | What | Models |
|---|---|---|
| [`dkms/hm1092-dell/`](dkms/hm1092-dell/) | **HM1092 IR sensor driver** (DKMS) — unmerged upstream driver + our reset and auto-IR-illuminator patches. *The key fix.* | 9340, 9350 |
| [`dkms/ipu6-isys-pmguard/`](dkms/ipu6-isys-pmguard/) | IPU6 boot-time crash fix (NULL deref race in runtime PM) | 9340 only (IPU7 already has the guard) |
| [`dkms/ipu-bridge-noir/`](dkms/ipu-bridge-noir/) | Fallback: RGB webcam **without** the IR driver (ignore the HM1092 entirely) | 9340 (would apply to 9350 too) |
| [`config/<model>/dracut/`](config/) | Keep camera drivers out of the initramfs (their firmware isn't declared, so they break after updates) | both |
| [`config/common/wireplumber/`](config/common/wireplumber/), [`config/<model>/wireplumber/`](config/) | Hide raw IPU capture nodes, name the cameras, fix a login timing race | both |
| [`patches/gaze/`](patches/gaze/) | [Gaze](https://github.com/GunduLabs/gaze) face authentication: use libcamera cameras (RGB + IR) | both |
| [`patches/v4l2-relayd/`](patches/v4l2-relayd/), [`config/xps13-9350/v4l2-relayd/`](config/xps13-9350/v4l2-relayd/) | "Virtual Camera" for V4L2-only apps such as **Zoom** | 9350 (9340 untested) |
| [`scripts/`](scripts/) | `check-cameras.sh` (read-only health check), Chrome camera permission fix, test helpers | both |
| [`docs/`](docs/) | Per-model walkthroughs, how it works, troubleshooting | — |

## Installation order (manual, for now)

Per-model step-by-step guides: **[docs/xps13-9340.md](docs/xps13-9340.md)** · **[docs/xps13-9350.md](docs/xps13-9350.md)**

1. **Kernel side** — HM1092 driver via DKMS (+ the IPU6 crash fix on the 9340), dracut omit file, reboot.
   Both cameras should then appear in `cam -l`.
2. **Desktop side** — WirePlumber files (user config). Apps then see "Front Camera" and "IR Camera".
3. **Optional extras** — Chrome/Meet permission fix, Zoom virtual camera, Gaze face unlock.

Run [`scripts/check-cameras.sh`](scripts/check-cameras.sh) at any point; it changes nothing.

## Credits and licences

- HM1092 driver: **Jake Steinman**, posted to linux-media in July 2026 (not yet merged);
  GPL-2.0-only. Our changes are in `dkms/hm1092-dell/patches/`.
- `ipu6-isys-pmguard` / `ipu-bridge-noir`: patches to Linux kernel files (GPL-2.0).
- Gaze: **Gundu Labs**, GPL-3.0-or-later; our patches in `patches/gaze/` are under the same licence.
- v4l2-relayd: **Canonical Ltd.**, GPL-2.0; our patch in `patches/v4l2-relayd/` likewise.
- Each directory keeps its upstream licence. See [LICENSE](LICENSE) for the files written for this repo.
