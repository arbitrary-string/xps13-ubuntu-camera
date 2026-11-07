#!/bin/bash
# Stage a DKMS source tree for one of the kernel-derived IPU6 fixes (Dell XPS 13 9340 only):
#   ipu6-isys-pmguard  - NULL-drvdata guard in the IPU6 ISYS runtime-PM suspend (boot-time crash fix)
#   ipu-bridge-noir    - drop HIMX1092 from ipu-bridge (RGB-only fallback when no HM1092 driver is used)
#
# The patched files are taken from the source of the running kernel (package linux-source-<ver>),
# so the result always matches the kernel being built for. Nothing is installed by this script.
#
# usage: dkms/prepare-source.sh <ipu6-isys-pmguard|ipu-bridge-noir> [output-dir]
set -euo pipefail

pkg=${1:?usage: $0 <ipu6-isys-pmguard|ipu-bridge-noir> [output-dir]}
here=$(cd "$(dirname "$0")" && pwd)
kver=$(uname -r)
kbase=${kver%%-*}                                 # e.g. 7.3.0
srcdir="/usr/src/linux-source-$kbase"
tarball=$(ls "$srcdir"/linux-source-"$kbase".tar.* 2>/dev/null | head -1 || true)
[ -n "$tarball" ] || { echo "Kernel source not found. Install it first: sudo apt install linux-source-$kbase" >&2; exit 1; }

version=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$here/$pkg/dkms.conf")
out=${2:-"$PWD/$pkg-$version"}
mkdir -p "$out"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

case "$pkg" in
  ipu6-isys-pmguard)
    tar -xf "$tarball" -C "$tmp" --wildcards "linux-source-$kbase/drivers/media/pci/intel/ipu6/*"
    d="$tmp/linux-source-$kbase/drivers/media/pci/intel/ipu6"
    cp "$d"/*.h "$out"/
    for f in ipu6-isys.c ipu6-isys-csi2.c ipu6-fw-isys.c ipu6-isys-video.c ipu6-isys-queue.c \
             ipu6-isys-subdev.c ipu6-isys-mcd-phy.c ipu6-isys-jsl-phy.c ipu6-isys-dwc-phy.c; do
      cp "$d/$f" "$out"/
    done
    patch -d "$out" ipu6-isys.c < "$here/$pkg/pmguard.patch"
    ;;
  ipu-bridge-noir)
    tar -xf "$tarball" -C "$tmp" "linux-source-$kbase/drivers/media/pci/intel/ipu-bridge.c"
    cp "$tmp/linux-source-$kbase/drivers/media/pci/intel/ipu-bridge.c" "$out"/
    patch -d "$out" ipu-bridge.c < "$here/$pkg/noir.patch"
    ;;
  *) echo "unknown package: $pkg" >&2; exit 1 ;;
esac

cp "$here/$pkg/dkms.conf" "$here/$pkg/Makefile" "$out"/
echo "Staged $pkg $version for kernel $kver in $out"
echo "Install with:  sudo cp -r $out /usr/src/ && sudo dkms install $pkg/$version  (then reboot)"
