#!/usr/bin/env bash
# unpacks QEMU's rv32 system emulator from the Debian packages into $WORK/qemu-deb, no root needed.
# (with root: sudo apt install qemu-system-riscv, and qemu-system-gui for the window.) Debian or Ubuntu x86-64.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. $HERE/env.sh
need apt-get dpkg
d=$WORK/qemu-deb
mkdir -p $d/root
cd $d
apt-get download qemu-system-riscv qemu-system-common qemu-system-data qemu-system-gui
for p in qemu-system-*.deb; do dpkg -x "$p" root; done
ls -l root/usr/bin/qemu-system-riscv32
