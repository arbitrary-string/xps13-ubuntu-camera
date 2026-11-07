# hm1092-dell — Himax HM1092 IR sensor driver (DKMS)

V4L2 sensor driver for the **Himax HM1092** monochrome near-IR sensor used for face authentication
on the Dell XPS 13 9340 (IPU6) and 9350 (IPU7). Installing it is what makes the **RGB webcam** work
too — see [docs/how-it-works.md](../../docs/how-it-works.md#problem-1--the-webcam-is-missing-entirely-kernel).

**License:** GPL-2.0-only (as the upstream driver).

## Provenance

- `upstream/hm1092.c` — **Jake Steinman**, "[PATCH 1/2] media: i2c: add Himax HM1092 IR sensor driver",
  linux-media, 2026-07-26 (archive: <https://lkml.iu.edu/2607.3/03798.html>). Unmerged at the time of
  writing. Developed on an IPU7 Dell XPS 16 with a 19.2 MHz sensor clock; 648×368 @ 30 fps, one CSI-2
  lane, 180.48 MHz link frequency. The register table was extracted from Dell's Windows driver.
- `hm1092.c` — upstream + the two patches below (this is what DKMS builds):
  - `patches/0001-reset-gpio.patch` — request the INT3472 `reset` GPIO (active low) and release it in
    `power_on`, assert it in `power_off`. Required on the **9340**, harmless no-op on the 9350.
  - `patches/0002-ir-flood-led.patch` — get the INT3472-registered LED (`devm_led_get(dev, "ir_flood")`)
    and switch it on/off with streaming, so the IR illuminator follows the camera automatically.

## Install

```bash
sudo cp -r . /usr/src/hm1092-dell-1.1        # from this directory
sudo dkms install hm1092-dell/1.1
# reboot
```

`AUTOINSTALL=yes`: DKMS rebuilds it for new kernels. Remove: `sudo dkms remove hm1092-dell/1.1 --all`.

## Expected result

```
$ sudo dmesg | grep -i hm1092
hm1092: loading out-of-tree module taints kernel.
i2c i2c-HIMX1092:00: deferred probe pending: hm1092: no endpoint found   # transient, then binds
$ cat /sys/class/video4linux/v4l-subdev*/name | grep hm1092
hm1092 15-0024
```

If the sensor doesn't answer, probe fails cleanly with `-ENODEV` ("failed to read chip ID") — the
webcam then stays broken but nothing else is affected.
