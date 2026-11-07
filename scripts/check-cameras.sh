#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Read-only health check for the Dell XPS 13 9340 (IPU6) / 9350 (IPU7) camera stack on Ubuntu.
# Changes nothing. Some checks need sudo (debugfs, initramfs listing); you may be asked for a password.
set -u
say() { printf '\n== %s\n' "$*"; }

say "Machine / kernel"
echo "$(sudo dmidecode -s system-product-name 2>/dev/null) | kernel $(uname -r)"
lspci -nn | grep -iE 'multimedia.*IPU' || echo "no Intel IPU found"

say "Camera unit firmware (failure here = camera drivers ran from the initramfs without firmware)"
sudo dmesg | grep -iE 'ipu[67].*(firmware load|failed with error)' || echo "no IPU firmware errors"

say "Sensor drivers"
for m in intel_ipu6_isys intel_ipu7_isys ov02c10 hm1092; do
  printf '%-16s %s\n' "$m" "$(lsmod | awk -v m=$m '$1==m{print "loaded"}' | head -1 || true)"
done
dkms status 2>/dev/null | grep -E 'hm1092|ipu6|ipu-bridge' || echo "(no camera DKMS packages)"

say "Sensors still waiting to bind (should list only headings, no fwnode lines)"
sudo cat /sys/kernel/debug/v4l2-async/pending_async_subdevices 2>/dev/null || echo "debugfs not available"

say "Sensor control nodes (ov02c10 must have one, or libcamera cannot use the webcam)"
for f in /sys/class/video4linux/v4l-subdev*/name; do printf '%s: %s\n' "$(basename "$(dirname "$f")")" "$(cat "$f")"; done 2>/dev/null

say "Camera drivers inside the boot image (should be none)"
sudo lsinitrd "/boot/initrd.img-$(uname -r)" 2>/dev/null | grep -iE 'ipu[67]|ipu-bridge|ivsc|intel_cvs|cvs/|ov02c10|hm1092' | awk '{print $NF}' || true
echo "(end of list)"

say "libcamera cameras (a camera that is streaming in another app is skipped here)"
cam -l 2>/dev/null | grep -E '^[0-9]+:' || echo "none (is libcamera-tools installed?)"
cam -l 2>&1 | grep -q 'Device or resource busy' && \
  echo "note: a camera is busy - another app (or the Zoom/V4L2 relay) is streaming it right now"

say "PipeWire camera sources (what apps see)"
wpctl status 2>/dev/null | sed -n '/^Video/,/^Settings/p' | sed -n '/Sources:/,/Filters:/p'

say "IR illuminator"
for l in /sys/class/leds/*ir_flood*; do [ -e "$l" ] && echo "$(basename "$l"): brightness $(cat "$l/brightness")"; done

say "Zoom/V4L2 virtual camera relay"
systemctl is-active 'v4l2-relayd@*' 2>/dev/null || echo "v4l2-relayd not running"
grep -l '^Virtual Camera$' /sys/devices/virtual/video4linux/*/name 2>/dev/null | cut -d/ -f6 || echo "no Virtual Camera device"
