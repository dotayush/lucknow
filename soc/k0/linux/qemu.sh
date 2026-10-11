#!/usr/bin/env bash
# runs the same kernel image on QEMU's rv32 virt machine, the reference for what k0 should print.
# k0 copies the virt memory map (uart, clint, plic, ram), so the image boots unchanged; QEMU makes its own
# device tree. QEMU has no sudo-free package on every host: set QEMU=<dir with qemu-system-riscv32> and
# QEMU_DATA=<dir with the firmware data> if it is not on PATH (see docs/LINUX.md).
#   ./linux/qemu.sh                           interactive, Ctrl-a x quits
#   IMAGE=Image ./linux/qemu.sh
#   WINDOW=1 ./linux/qemu.sh                  the console in a window of its own (needs the gtk display module:
#                                             QEMU_MODULES=<dir with ui-gtk.so>, and a $DISPLAY)
#   printf 'uname -m\n' | ./linux/qemu.sh     typed input from a pipe
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/out}
Q=${QEMU:+$QEMU/}qemu-system-riscv32
[ -n "${QEMU_DATA:-}" ] && L=(-L $QEMU_DATA) || L=()
[ -n "${QEMU_MODULES:-}" ] && export QEMU_MODULE_DIR=$QEMU_MODULES
if [ -n "${WINDOW:-}" ]; then D=(-display gtk,zoom-to-fit=off -serial vc:100Cx30C -monitor none); else D=(-nographic); fi
exec $Q -M virt -cpu rv32 -m 16M -smp 1 "${D[@]}" -bios none "${L[@]}" \
  -kernel $OUT/${IMAGE:-Image.busybox} -append "console=ttyS0" "$@"
