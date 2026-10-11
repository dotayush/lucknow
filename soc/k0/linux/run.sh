#!/usr/bin/env bash
# runs the kernel built by build.sh on the verilator model (sim/build.sh first).
#   ./linux/run.sh                          boots, stops at the shell prompt
#   RX=file.txt STOP="text" ./linux/run.sh  types the file at the shell and stops when the console printed STOP
#   MAX=<clocks> TRACE=<file>               cycle limit (default 300e6), retired pc trace
#   RX_DELAY=<clocks> RX_GAP=<bit times>    when typing starts (default 60e6), idle bits between bytes (default 60:
#                                           the uart has no fifo, the kernel needs time for each byte)
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/out}
args=(+image=$OUT/Image +image=$OUT/k0.dtb@807f0000 +max_cycles=${MAX:-300000000} "+stop_on=${STOP:-k0# |end Kernel panic}")
[ -n "${RX:-}" ] && args+=(+rx=$RX +rx_delay=${RX_DELAY:-60000000} +rx_gap=${RX_GAP:-60})
[ -n "${TRACE:-}" ] && args+=(+trace=$TRACE)
exec $HERE/../sim/obj/Vsoc "${args[@]}"
