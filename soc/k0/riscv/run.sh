#!/usr/bin/env bash
# riscv-tests for k0: rv32ui + rv32mi + rv32um + rv32ua, linked at the ram base. same harness as core/l0, see its run.sh.
# fence_i is included: instruction and data port see the same memory.
# wait states: RV_IFLAGS="-Ptest_riscv.FETCH_WAIT=2 -Ptest_riscv.DATA_WAIT=3" ./riscv/run.sh
here=$(cd "$(dirname "$0")" && pwd)
CORE="$here/.." RV_MARCH=rv32ima_zicsr_zifencei RV_UM=1 RV_UA=1 RV_BASE=0x80000000 RV_UI_SKIP="ma_data" exec "$here/../../../core/l0/riscv/run.sh" "$@"
