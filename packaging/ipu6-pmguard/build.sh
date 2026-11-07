#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# DKMS build step for ipu6-isys-pmguard (Dell XPS 13 9340 / Intel IPU6 only).
# Extracts the IPU6 ISYS sources of the kernel being built for from the matching
# linux-source-<x.y.z> package, applies pmguard.patch and builds intel-ipu6-isys.ko.
#
# usage (from dkms.conf): build.sh <kernelver> <kernel_source_dir> [extra make args...]
set -eu
kver=$1
ksrc=$2
kbase=${kver%%-*}
tarball=$(ls /usr/src/linux-source-"$kbase"/linux-source-"$kbase".tar.* 2>/dev/null | head -n 1 || true)
if [ -z "$tarball" ]; then
	echo "ipu6-isys-pmguard: kernel source for $kbase not found." >&2
	echo "Install it with:  sudo apt install linux-source-$kbase" >&2
	exit 1
fi

here=$(pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tar -xf "$tarball" -C "$tmp" --wildcards "linux-source-$kbase/drivers/media/pci/intel/ipu6/*"
src="$tmp/linux-source-$kbase/drivers/media/pci/intel/ipu6"
cp "$src"/*.h "$here"/
for f in ipu6-isys.c ipu6-isys-csi2.c ipu6-fw-isys.c ipu6-isys-video.c ipu6-isys-queue.c \
	 ipu6-isys-subdev.c ipu6-isys-mcd-phy.c ipu6-isys-jsl-phy.c ipu6-isys-dwc-phy.c; do
	cp "$src/$f" "$here"/
done
patch -p0 --forward -s ipu6-isys.c < "$here/pmguard.patch"

make -C "$ksrc" M="$here" modules
