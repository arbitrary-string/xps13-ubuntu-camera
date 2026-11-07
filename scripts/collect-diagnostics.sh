#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Collect camera diagnostics for xps13-ubuntu-camera into one text file. Read-only: changes no
# settings and restarts nothing; it only reads logs/config and runs short capture tests (the
# webcam turns on briefly, the IR illuminator may flash). Some steps use sudo.
#
# usage: collect-diagnostics.sh [output-file]      (default: ~/xps13-camera-diagnostics.txt)
set -u
OUT=${1:-$HOME/xps13-camera-diagnostics.txt}
exec > >(tee "$OUT") 2>&1
say() { printf '\n===== %s\n' "$*"; }
filter() { grep -vE 'Unable to get rectangle|PixelArray|crop rectangle|kernel driver needs|sensor_driver_requirements|No static properties|sensor delays|properties database|EGL_EXTENSIONS'; }

say "versions"
uname -r
dpkg-query -W xps13-ubuntu-camera v4l2-relayd wireplumber libcamera0.7 pipewire 2>/dev/null
xps13-camera-setup 2>&1

say "WirePlumber config fragments (device.disabled here can hang WirePlumber)"
for d in "$HOME/.config/wireplumber/wireplumber.conf.d" /etc/wireplumber/wireplumber.conf.d /usr/share/wireplumber/wireplumber.conf.d; do
	echo "-- $d"; ls -1 "$d" 2>/dev/null
done
grep -rn 'disabled' "$HOME/.config/wireplumber" /etc/wireplumber /usr/share/wireplumber/wireplumber.conf.d 2>/dev/null | grep -v ':[[:space:]]*#'
ls -1 "$HOME/.config/systemd/user/wireplumber.service.d" 2>/dev/null

say "PipeWire audio + video (wpctl status)"
wpctl status 2>&1 | sed -n '/^Audio/,/^Settings/p' | grep -vE '^\s*│\s*$' | grep -vE 'ipu[67] +\[v4l2\]'

say "WirePlumber log this boot (camera-related)"
journalctl --user -b -u wireplumber --no-pager -o short-monotonic 2>/dev/null | filter | grep -iE 'disabled|denied|error|fail|libcamera|camera|Adding' | head -40

say "relay service"
systemctl status 'v4l2-relayd@*' --no-pager 2>&1 | head -12
cat /etc/v4l2-relayd.d/*.conf 2>/dev/null | grep -E '^(VIDEOSRC|SPLASHSRC|FORMAT|WIDTH|HEIGHT|FRAMERATE|CARD_LABEL)'
pid=$(systemctl show -p MainPID --value 'v4l2-relayd@xps13-webcam' 2>/dev/null)
[ -n "$pid" ] && [ "$pid" != 0 ] && ps -o args= -p "$pid"
journalctl -b -u 'v4l2-relayd@*' --no-pager -o short-monotonic 2>/dev/null | filter | tail -40

dev=/dev/$(grep -l -m1 '^Virtual Camera$' /sys/devices/virtual/video4linux/*/name 2>/dev/null | cut -d/ -f6)
rgb=$(xps13-camera-setup --camera-id 2>/dev/null)
idx=$(cam -l 2>/dev/null | grep -F "($rgb)" | sed -E 's/^([0-9]+):.*/\1/')
frames() { echo "$(( $1 / $2 ))"; }

say "TEST 1: Virtual Camera as a V4L2 app sees it ($dev, 90 frames, 15 s limit)"
v4l2-ctl -d "$dev" --list-formats-ext 2>&1 | head -6
b=$(timeout 15 v4l2-ctl -d "$dev" --stream-mmap --stream-count=90 --stream-to=- 2>/dev/null | wc -c)
echo "received $(frames "$b" 1843200)/90 frames"
journalctl -b -u 'v4l2-relayd@*' --no-pager -o short-monotonic --since "-25s" 2>/dev/null | filter | tail -15
sleep 3

say "TEST 2: libcamera directly (cam, camera $idx = $rgb, 30 frames)"
timeout 20 cam -c"$idx" --capture=30 2>&1 | filter | grep -E 'fps|ERROR|WARN|error' | tail -8
sleep 2

say "TEST 3: the relay's input pipeline on its own, clock-synced sink (30 frames, 15 s limit)"
esc=$(printf '%s' "$rgb" | sed 's/\\/\\\\/g')
for sync in false true; do
	s=$(date +%s%N)
	timeout 15 gst-launch-1.0 -q libcamerasrc camera-name="$esc" ! videoconvert ! videoscale \
		! 'video/x-raw,format=YUY2,width=1280,height=720,framerate=30/1' ! identity eos-after=30 ! fakesink sync=$sync >/dev/null 2>&1
	echo "sink sync=$sync: exit=$? (0 = 30 frames, 124 = stalled) in $(( ($(date +%s%N)-s)/1000000 )) ms"
	sleep 2
done

say "kernel messages (IPU / sensors) this boot"
sudo dmesg 2>/dev/null | grep -iE 'ipu6|ipu7|isys|ivsc|cvs|ov02c10|hm1092|v4l2loopback' | grep -vE 'firmware cpd file|Name: |Version: |Timestamp: |Commit: |FW binary' | tail -30

say "done - results saved to $OUT"
