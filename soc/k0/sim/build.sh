#!/usr/bin/env bash
# builds the verilator model of the soc into sim/obj/Vsoc. run from anywhere.
#   RAM_WORDS=2097152 CPB=256 ./sim/build.sh
#     RAM_WORDS  default 2097152 = 8 MiB, what the linux device tree says
#     CPB        uart clocks per bit, default 256. the uart has no fifo: the kernel's interrupt handler needs
#                a few thousand clocks per byte, so a typed line is only safe with a slow uart
# then: ./sim/obj/Vsoc +image=<file> [+rx=<file>] [+stop_on=<text>] ...  (see sim_main.cpp)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
K0=$HERE/..
cd $K0
verilator --cc --exe --build -j 0 -O3 --public-flat-rw -Wno-fatal -Wno-lint -Wno-style \
  --top-module soc -GRAM_WORDS=${RAM_WORDS:-2097152} -GUART_CLKS_PER_BIT=${CPB:-256} -CFLAGS -DCLKS_PER_BIT=${CPB:-256} -GROM_INIT=\"$K0/memory/bootrom.hex\" \
  -Mdir $HERE/obj -o Vsoc -f compile.f $HERE/sim_main.cpp
