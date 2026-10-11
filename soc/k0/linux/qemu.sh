#!/usr/bin/env bash
# runs the same kernel image on QEMU's rv32 virt machine, the reference for what k0 should print.
# k0 copies the virt memory map (uart, clint, plic, ram), so the image boots unchanged; QEMU makes its own
# device tree. it boots in a second or two where the Verilator model takes a minute.
#   ./linux/qemu.sh                           the console in this terminal, Ctrl-a x quits
#   IMAGE=Image ./linux/qemu.sh               the small built-in shell instead of busybox
#   WINDOW=1 ./linux/qemu.sh                  the console in a window of its own (needs a $DISPLAY)
#   printf 'uname -m\n' | ./linux/qemu.sh     typed input from a pipe
# qemu-system-riscv32 is taken from PATH, else from $WORK/qemu-deb (./linux/qemu-fetch.sh puts it there
# without root). QEMU=<dir with the binary>, QEMU_DATA=<share/qemu dir>, QEMU_MODULES=<dir with ui-gtk.so>
# override what is found.
HERE=$(cd "$(dirname "$0")" && pwd)
. $HERE/env.sh
OUT=${OUT:-$HERE/out}
local_root=$WORK/qemu-deb/root/usr
if ! command -v ${QEMU:+$QEMU/}qemu-system-riscv32 >/dev/null 2>&1; then
  if [ -x $local_root/bin/qemu-system-riscv32 ]; then
    QEMU=${QEMU:-$local_root/bin}
    QEMU_DATA=${QEMU_DATA:-$local_root/share/qemu}
    QEMU_MODULES=${QEMU_MODULES:-$local_root/lib/x86_64-linux-gnu/qemu}
  else
    echo "qemu-system-riscv32 not found: install qemu-system-riscv, or run ./linux/qemu-fetch.sh (no root needed)" >&2
    exit 1
  fi
fi
Q=${QEMU:+$QEMU/}qemu-system-riscv32
[ -n "${QEMU_DATA:-}" ] && L=(-L $QEMU_DATA) || L=()
[ -n "${QEMU_MODULES:-}" ] && export QEMU_MODULE_DIR=$QEMU_MODULES
if [ -n "${WINDOW:-}" ]; then D=(-display gtk,zoom-to-fit=off -serial vc:100Cx30C -monitor none); else D=(-nographic); fi
[ -f $OUT/${IMAGE:-Image.busybox} ] || { echo "$OUT/${IMAGE:-Image.busybox} is not built (see docs/LINUX.md)" >&2; exit 1; }
exec $Q -M virt -cpu rv32 -m 16M -smp 1 "${D[@]}" -bios none "${L[@]}" \
  -kernel $OUT/${IMAGE:-Image.busybox} -append "console=ttyS0" "$@"
