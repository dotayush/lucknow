#!/usr/bin/env bash
# builds the k0 linux image: init (flat binary), initramfs list, device tree. the kernel itself is built
# in $LINUX (a linux 6.12 tree, see docs/PLAN.md): this script configures and builds it too.
#   ./linux/build.sh                        downloads linux 6.12.112 into $WORK (default ~/personal/k0-linux)
#   LINUX=<tree> ./linux/build.sh           uses a tree you already have (6.12.x)
# the kernel build needs bc, flex, bison and make (linux/env.sh checks, and finds tools built without root
# in $WORK/tools/bin; BC_PATH=<dir> adds a directory to PATH).
# outputs in $OUT (default linux/out): Image, k0.dtb, init.flat
set -eu

# set up paths and versions
HERE=$(cd "$(dirname "$0")" && pwd)
. $HERE/env.sh
KVER=6.12.112
WORK=${WORK:-$HOME/personal/k0-linux}
LINUX=${LINUX:-$WORK/src/linux-$KVER}
OUT=${OUT:-$HERE/out}
TC=${TOOLCHAIN:-/opt/riscv32/bin/riscv32-unknown-elf-}
need bc flex bison make python3 curl ${TC}gcc

# fetch linux if not already there
if [ ! -d $LINUX ]; then
  mkdir -p $WORK/dl $WORK/src
  curl -fL -o $WORK/dl/linux-$KVER.tar.xz https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz
  tar -C $WORK/src -xf $WORK/dl/linux-$KVER.tar.xz
fi

# build init: freestanding, position independent, no compressed instructions
mkdir -p $OUT/init
${TC}gcc -march=rv32ima_zicsr -mabi=ilp32 -Os -fPIE -static -mcmodel=medany -ffreestanding -nostdlib -nostartfiles -fno-asynchronous-unwind-tables -fno-stack-protector -Wl,--no-warn-rwx-segments -Wl,-z,norelro -T $HERE/init/link.ld $HERE/init/init.c -o $OUT/init/init.elf
${TC}objcopy -O binary $OUT/init/init.elf $OUT/init/init.bin

# compute the size of the bss section and make a flat binary with it
bss=$(${TC}nm $OUT/init/init.elf | awk '$3=="_bss_end"{e=$1} $3=="_data_end"{d=$1} END{print strtonum("0x"e)-strtonum("0x"d)}')
python3 -I $HERE/init/mkflat.py $OUT/init/init.bin $OUT/init.flat $bss
if ${TC}readelf -r $OUT/init/init.elf | grep -q "R_RISCV"; then echo "init has relocations, the flat file has none"; exit 1; fi

# make the initramfs list for the kernel build, replacing @INIT@ with the path to the flat init binary
sed "s|@INIT@|$OUT/init.flat|" $HERE/initramfs.list > $OUT/initramfs.list

# build the kernel: configure, set the initramfs source, build the device tree and the kernel image
export CROSS_COMPILE=$TC ARCH=riscv
cp $HERE/k0_defconfig $LINUX/arch/riscv/configs/k0_defconfig
make -C $LINUX k0_defconfig >/dev/null
$LINUX/scripts/config --file $LINUX/.config --set-str INITRAMFS_SOURCE $OUT/initramfs.list
make -C $LINUX olddefconfig >/dev/null
make -C $LINUX scripts_dtc >/dev/null

# build the device tree and the kernel image
$LINUX/scripts/dtc/dtc -I dts -O dtb -o $OUT/k0.dtb $HERE/k0.dts
make -C $LINUX -j$(nproc) Image
cp $LINUX/arch/riscv/boot/Image $OUT/Image
ls -la $OUT/Image $OUT/k0.dtb $OUT/init.flat
