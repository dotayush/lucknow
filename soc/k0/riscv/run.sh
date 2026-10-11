#!/usr/bin/env bash
# riscv-tests for k0: rv32ui + rv32mi + rv32um. same harness as core/l0, see its run.sh.
here=$(cd "$(dirname "$0")" && pwd)
CORE="$here/.." RV_MARCH=rv32im_zicsr RV_UM=1 exec "$here/../../../core/l0/riscv/run.sh" "$@"
