#!/usr/bin/env bash
# builds a no mmu rv32ima userland (uClibc-ng toolchain, busybox, flat binaries) with buildroot.
#   ./linux/buildroot/build.sh        output: $OUT/rootfs.cpio (default linux/out), takes 20 to 40 minutes
# buildroot is downloaded to $WORK (default ~/personal/k0-linux) the first time. needs the usual host
# tools buildroot lists (gcc, make, patch, perl, python3, cpio, rsync, wget, unzip, bc, file).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
BRVER=2025.02.7
WORK=${WORK:-$HOME/personal/k0-linux}
BR=${BR:-$WORK/src/buildroot-$BRVER}
OUT=${OUT:-$HERE/../out}
BRO=$WORK/br-out
if [ ! -d $BR ]; then
  mkdir -p $WORK/dl $WORK/src
  curl -fL -o $WORK/dl/buildroot-$BRVER.tar.xz https://buildroot.org/downloads/buildroot-$BRVER.tar.xz
  tar -C $WORK/src -xf $WORK/dl/buildroot-$BRVER.tar.xz
fi
[ -n "${BC_PATH:-}" ] && export PATH=$BC_PATH:$PATH
# buildroot refuses empty entries (meaning ".") in PATH and LD_LIBRARY_PATH
clean() { printf '%s' "$1" | tr ':' '\n' | grep -v '^$' | paste -sd: -; }
export PATH=$(clean "$PATH")
export LD_LIBRARY_PATH=$(clean "${LD_LIBRARY_PATH:-}")
mkdir -p $BRO $OUT
# a br2-external tree is just a directory with these three files
ext=$WORK/br-external
mkdir -p $ext
printf 'name: K0\ndesc: k0 userland\n' > $ext/external.desc
: > $ext/external.mk
: > $ext/Config.in
rm -f $ext/overlay
ln -s $HERE/overlay $ext/overlay
cp $HERE/k0_defconfig $ext/k0_defconfig
rm -f $ext/post-build.sh $ext/src
ln -s $HERE/post-build.sh $ext/post-build.sh
ln -s $HERE/src $ext/src
make -C $BR O=$BRO BR2_EXTERNAL=$ext BR2_DEFCONFIG=$ext/k0_defconfig defconfig
make -C $BR O=$BRO BR2_EXTERNAL=$ext -j$(nproc)
cp $BRO/images/rootfs.cpio $OUT/rootfs.cpio
ls -l $OUT/rootfs.cpio
