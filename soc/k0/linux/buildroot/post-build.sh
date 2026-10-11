#!/bin/sh
# buildroot runs this with the target root as $1, after the packages are installed: builds the small
# programs of this directory with the cross compiler that was just built (flat binaries through elf2flt)
set -e
SRC=$(dirname "$0")/src
$HOST_DIR/bin/riscv32-buildroot-linux-uclibc-gcc -Os -fPIC -Wl,-elf2flt="-r -s16384" -o $1/usr/bin/hpmstat $SRC/hpmstat.c
