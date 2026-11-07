# ipu6-isys-pmguard — IPU6 boot-time crash fix (DKMS, XPS 13 9340)

`isys_runtime_pm_suspend()` in `drivers/media/pci/intel/ipu6/ipu6-isys.c` can run while
`isys_probe()` is still before `dev_set_drvdata()`, dereferencing a NULL `isys` (`isys+0x31c`,
`spin_lock_irqsave(&isys->power_lock)`) and panicking the kernel during boot — about one boot in a
few on the 9340 with kernel 7.3.

`pmguard.patch` (GPL-2.0, against the 7.3 kernel source) returns `-EBUSY` from runtime suspend and `0`
from system suspend while the driver data is not set yet; runtime PM simply retries later.
**IPU7 (XPS 13 9350) already contains an equivalent guard — not needed there.**

## Build

The DKMS tree is generated from your own kernel's source so it always matches:

```bash
sudo apt install linux-source-$(uname -r | cut -d- -f1)
../prepare-source.sh ipu6-isys-pmguard /tmp/ipu6-isys-pmguard-1.0
sudo cp -r /tmp/ipu6-isys-pmguard-1.0 /usr/src/ && sudo dkms install ipu6-isys-pmguard/1.0
# reboot
```

Verified: 6+ consecutive clean boots after installing, versus 1 crash in 2 boots before.
