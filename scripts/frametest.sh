#!/bin/bash
# usage: frametest.sh <libcamera camera name> ; prints exit code and seconds for 30 frames
s=$(date +%s%N)
timeout 15 gst-launch-1.0 -q libcamerasrc camera-name="$1" ! 'video/x-raw,pixel-aspect-ratio=1/1' ! identity eos-after=30 ! videoconvert ! videoscale ! 'video/x-raw,format=BGR' ! fakesink 2>&1 | grep -iE "error|erroneous|no element|could not" | head -3
rc=$?
e=$(date +%s%N)
echo "exit=$rc (0=got 30 frames, 124=timed out) time=$(( (e-s)/1000000 ))ms"
