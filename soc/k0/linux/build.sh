#!/usr/bin/env bash
# builds the k0 linux image: init (flat binary), initramfs list, device tree. the kernel itself is built
# in $LINUX (a linux 6.12 tree, see docs/PLAN.md): this script configures and builds it too.
#   ./linux/build.sh                        downloads linux 6.12.112 into $WORK (default ~/personal/k0-linux)
#   LINUX=<tree> ./linux/build.sh           uses a tree you already have (6.12.x)
# the kernel build needs bc, flex, bison and make. BC_PATH=<dir with bc> adds a directory to PATH for it.
# outputs in $OUT (default linux/out): Image, k0.dtb, init.flat
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
KVER=6.12.112
WORK=${WORK:-$HOME/personal/k0-linux}
LINUX=${LINUX:-$WORK/src/linux-$KVER}
if [ ! -d $LINUX ]; then
  mkdir -p $WORK/dl $WORK/src
  curl -fL -o $WORK/dl/linux-$KVER.tar.xz https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz
  tar -C $WORK/src -xf $WORK/dl/linux-$KVER.tar.xz
fi
OUT=${OUT:-$HERE/out}
TC=${TOOLCHAIN:-/opt/riscv32/bin/riscv32-unknown-elf-}
mkdir -p $OUT/init

# init: freestanding, position independent, no compressed instructions
${TC}gcc -march=rv32ima_zicsr -mabi=ilp32 -Os -fPIE -static -mcmodel=medany -ffreestanding -nostdlib -nostartfiles \
  -fno-asynchronous-unwind-tables -fno-stack-protector -Wl,--no-warn-rwx-segments \
  -Wl,-z,norelro -T $HERE/init/link.ld $HERE/init/init.c -o $OUT/init/init.elf
${TC}objcopy -O binary $OUT/init/init.elf $OUT/init/init.bin
bss=$(${TC}nm $OUT/init/init.elf | awk '$3=="_bss_end"{e=$1} $3=="_data_end"{d=$1} END{print strtonum("0x"e)-strtonum("0x"d)}')
python3 -I $HERE/init/mkflat.py $OUT/init/init.bin $OUT/init.flat $bss
if ${TC}readelf -r $OUT/init/init.elf | grep -q "R_RISCV"; then echo "init has relocations, the flat file has none"; exit 1; fi

# initramfs: the init and a console node
sed "s|@INIT@|$OUT/init.flat|" $HERE/initramfs.list > $OUT/initramfs.list

# kernel
export CROSS_COMPILE=$TC ARCH=riscv
[ -n "${BC_PATH:-}" ] && export PATH=$BC_PATH:$PATH
cp $HERE/k0_defconfig $LINUX/arch/riscv/configs/k0_defconfig
make -C $LINUX k0_defconfig >/dev/null
$LINUX/scripts/config --file $LINUX/.config --set-str INITRAMFS_SOURCE $OUT/initramfs.list
make -C $LINUX olddefconfig >/dev/null
make -C $LINUX scripts_dtc >/dev/null
# device tree
$LINUX/scripts/dtc/dtc -I dts -O dtb -o $OUT/k0.dtb $HERE/k0.dts
make -C $LINUX -j$(nproc) Image
cp $LINUX/arch/riscv/boot/Image $OUT/Image
ls -la $OUT/Image $OUT/k0.dtb $OUT/init.flat
