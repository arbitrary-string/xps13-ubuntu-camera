# v4l2-relayd patch — working "Virtual Camera" for Zoom and other V4L2-only apps

[v4l2-relayd](https://launchpad.net/ubuntu/+source/v4l2-relayd) (Canonical Ltd., GPL-2.0) relays a
GStreamer source into a `v4l2loopback` device and starts the real camera only while an app has the
virtual one open. Ubuntu's 0.2.0 stalls here after a few frames: the relay sets its input pipeline's
base time to the output pipeline's, sources stamp buffers on their own timeline, and `v4l2sink` drops
every frame as late (it happens even with `videotestsrc`). `libcamerasrc` additionally stalls a
clock-synchronised appsink.

`0001-fix-timestamps-and-appsink-sync.patch` (GPL-2.0):
- input `appsink`: `sync = FALSE`;
- hand frames to the output with PTS/DTS/duration cleared (shallow buffer copy);
- output `appsrc`: `do-timestamp = TRUE` (re-stamped with the current running time).

## Build

```bash
sudo apt install v4l2-relayd build-essential pkg-config libglib2.0-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
curl -LO https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/v4l2-relayd/0.2.0-0ubuntu2/v4l2-relayd_0.2.0.orig.tar.gz
tar xf v4l2-relayd_0.2.0.orig.tar.gz && cd v4l2-relayd-0.2.0
patch -p1 < /path/to/this/repo/patches/v4l2-relayd/0001-fix-timestamps-and-appsink-sync.patch
echo '#define V4L2_RELAYD_VERSION "0.2.0-local1"' > config.h
gcc -O2 -Wall -DHAVE_CONFIG_H -I. -o v4l2-relayd src/v4l2-relayd.c \
  $(pkg-config --cflags --libs glib-2.0 gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0)

sudo dpkg-divert --add --rename --divert /usr/bin/v4l2-relayd.distrib /usr/bin/v4l2-relayd
sudo install -m 0755 v4l2-relayd /usr/bin/v4l2-relayd
```

Then install `config/xps13-9350/v4l2-relayd/webcam.conf` into `/etc/v4l2-relayd.d/` (the instance
file; note the 8 backslashes and the caps-free pipelines — explained in the file) and reboot.

Tested on the 9350: 90/90 frames at ~30 fps per client, reconnects work, the real camera is off while
no app uses the virtual one.
