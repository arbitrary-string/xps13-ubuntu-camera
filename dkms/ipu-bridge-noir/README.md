# ipu-bridge-noir — RGB webcam without the IR sensor (fallback, DKMS)

Removes the `HIMX1092` entry from `drivers/media/pci/intel/ipu-bridge.c` (`noir.patch`, GPL-2.0), so
the IPU capture driver no longer waits for the IR sensor and creates the RGB sensor's node.

Use this **instead of** `hm1092-dell` only if you want the webcam but not the IR camera, or if the
HM1092 driver doesn't work on your machine. Never install both.

```bash
sudo apt install linux-source-$(uname -r | cut -d- -f1)
../prepare-source.sh ipu-bridge-noir /tmp/ipu-bridge-noir-1.0
sudo cp -r /tmp/ipu-bridge-noir-1.0 /usr/src/ && sudo dkms install ipu-bridge-noir/1.0
# reboot
```

Tested on the 9340 (IPU6). The same `ipu-bridge` module serves IPU7, so it should work on the 9350,
but that was not tested.
