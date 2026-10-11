#!/usr/bin/env bash
# builds a bare-metal program from programs/<name>.S, runs it on the soc and checks the uart output.
#   ./programs/run.sh              runs hello
#   ./programs/run.sh hello
# needs riscv32-unknown-elf-gcc (TOOLCHAIN) and iverilog. run from anywhere.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
K0=$HERE/..
TOOLCHAIN=${TOOLCHAIN:-/opt/riscv32/bin/riscv32-unknown-elf-}
name=${1:-hello}
BUILD=$K0/programs/build
mkdir -p $BUILD

${TOOLCHAIN}gcc -march=rv32ima_zicsr -mabi=ilp32 -nostdlib -nostartfiles -Ttext=0x80000000 \
  -Wl,--no-warn-rwx-segments $HERE/$name.S -o $BUILD/$name.elf || exit 1
${TOOLCHAIN}objcopy -O binary $BUILD/$name.elf $BUILD/$name.bin
od -An -v -tx4 -w4 $BUILD/$name.bin | tr -d ' ' > $BUILD/$name.hex

cd $K0 || exit 1
iverilog -g2012 -o $BUILD/$name.out -Ptest_hello.IMAGE=\"$BUILD/$name.hex\" \
  -c compile.f tests/test_hello.sv || exit 1
vvp -n $BUILD/$name.out | grep -E "^(PASS|FAIL|  \[)"
