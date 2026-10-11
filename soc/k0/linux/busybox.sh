#!/usr/bin/env bash
# rebuilds the kernel with the buildroot root filesystem (buildroot/build.sh first, and build.sh once so the
# kernel tree is configured) and boots it to the busybox shell. output: $OUT/Image.busybox
#   ./linux/busybox.sh                 build the kernel image
#   RUN=1 ./linux/busybox.sh           also boot it on the verilator model, typing RX (default: a few commands)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
KVER=6.12.112
WORK=${WORK:-$HOME/personal/k0-linux}
LINUX=${LINUX:-$WORK/src/linux-$KVER}
OUT=${OUT:-$HERE/out}
TC=${TOOLCHAIN:-/opt/riscv32/bin/riscv32-unknown-elf-}
export CROSS_COMPILE=$TC ARCH=riscv
[ -n "${BC_PATH:-}" ] && export PATH=$BC_PATH:$PATH
$LINUX/scripts/config --file $LINUX/.config --set-str INITRAMFS_SOURCE $OUT/rootfs.cpio
make -C $LINUX olddefconfig >/dev/null
make -C $LINUX -j$(nproc) Image
cp $LINUX/arch/riscv/boot/Image $OUT/Image.busybox
ls -l $OUT/Image.busybox
