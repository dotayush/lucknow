#!/usr/bin/env bash
# builds and runs the riscv-tests isa suites against a core.
#   ./riscv/run.sh            run everything in the lists below
#   ./riscv/run.sh addi lw    run only the named tests
# the core is the directory above this script (core/l0), or $CORE. it needs a compile.f
# (rtl only paths + nothing from tests/) and a tests/test_riscv.sv. other cores reuse this
# script, see soc/k0/riscv/run.sh. knobs (environment):
#   RV_MARCH     -march for the tests, default rv32i_zicsr
#   RV_UM=1      also run rv32um
#   RV_UA=1      also run rv32ua
#   RV_BASE      address the image is linked at (ram base), default 0
#   RV_UI_SKIP   rv32ui tests not to run
#   RV_IFLAGS    extra iverilog flags, for example -Ptest_riscv.DATA_WAIT=3
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
CORE=$(cd "${CORE:-$HERE/..}" && pwd)
RV_MARCH=${RV_MARCH:-rv32i_zicsr}
RV_UM=${RV_UM:-0}
RV_UA=${RV_UA:-0}
RV_BASE=${RV_BASE:-0}
RV_IFLAGS=${RV_IFLAGS:-}
cd "$CORE" || exit 1

RISCV_TESTS_REV=7b68f7b91f827f8d94cc1c57ff123752c5c8f704
TOOLCHAIN=${TOOLCHAIN:-/opt/riscv32/bin/riscv32-unknown-elf-}
SRC=$HERE/../riscv-tests
BUILD=$CORE/riscv/build

# rv32ui-p-*: everything except tests the core can't run
#   fence_i: needs a writable instruction memory (zifencei)
#   ma_data: needs misaligned data access to be handled in hardware
UI_SKIP=${RV_UI_SKIP:-"fence_i ma_data"}
# rv32mi-p-*: machine-mode tests. not run:
#   illegal: exercises vectored mtvec and software interrupts (mip/mideleg), the core has no interrupts
#   instret_overflow: needs minstret/minstreth
#   breakpoint: needs the debug trigger module (tselect/tdata)
MI_TESTS="csr mcsr scall sbreak shamt ma_addr ma_fetch lh-misaligned lw-misaligned sh-misaligned sw-misaligned zicntr pmpaddr"
# rv32um-p-*: everything, when the core has the m extension
UM_TESTS="mul mulh mulhsu mulhu div divu rem remu"
# rv32ua-p-*: the word atomics, when the core has the a extension
UA_TESTS="lrsc amoswap_w amoadd_w amoxor_w amoand_w amoor_w amomin_w amomax_w amominu_w amomaxu_w"

if [ ! -d $SRC ]; then
  git clone -q --recurse-submodules https://github.com/riscv-software-src/riscv-tests $SRC || exit 1
  git -C $SRC checkout -q $RISCV_TESTS_REV && git -C $SRC submodule update -q --init --recursive || exit 1
fi

mkdir -p $BUILD
grep -v "^./tests/" compile.f > $BUILD/core.f # the rtl only, without test_control

tests=()
if [ $# -gt 0 ]; then
  for t in "$@"; do
    if [ -f $SRC/isa/rv32ui/$t.S ]; then tests+=("rv32ui/$t")
    elif [ -f $SRC/isa/rv32mi/$t.S ]; then tests+=("rv32mi/$t")
    elif [ -f $SRC/isa/rv32ua/$t.S ]; then tests+=("rv32ua/$t")
    else tests+=("rv32um/$t"); fi
  done
else
  for f in $SRC/isa/rv32ui/*.S; do
    t=$(basename $f .S)
    case " $UI_SKIP " in *" $t "*) continue ;; esac
    tests+=("rv32ui/$t")
  done
  for t in $MI_TESTS; do tests+=("rv32mi/$t"); done
  if [ "$RV_UM" = 1 ]; then for t in $UM_TESTS; do tests+=("rv32um/$t"); done; fi
  if [ "$RV_UA" = 1 ]; then for t in $UA_TESTS; do tests+=("rv32ua/$t"); done; fi
fi

pass=0; fail=0; failed=()
for t in "${tests[@]}"; do
  name=rv32${t#rv32}; name=${name/\//-p-}
  elf=$BUILD/$name.elf
  ${TOOLCHAIN}gcc -march=$RV_MARCH -mabi=ilp32 -static -mcmodel=medany -nostdlib -nostartfiles \
    -I $SRC/env/p -I $SRC/isa/macros/scalar -Wl,--no-warn-rwx-segments -Wl,--defsym=RAM_BASE=$RV_BASE -T $HERE/link.ld $SRC/isa/$t.S -o $elf || { echo "$name: BUILD FAILED"; fail=$((fail+1)); failed+=($name); continue; }
  ${TOOLCHAIN}objcopy -O binary $elf $BUILD/$name.bin
  od -An -v -tx4 -w4 $BUILD/$name.bin | tr -d ' ' > $BUILD/$name.hex
  tohost=$(${TOOLCHAIN}nm $elf | awk '$3=="tohost"{print $1}')
  iverilog -g2012 -o $BUILD/$name.out -Ptest_riscv.IMAGE=\"$BUILD/$name.hex\" -Ptest_riscv.TOHOST=\'h$tohost \
    $RV_IFLAGS -c $BUILD/core.f tests/test_riscv.sv 2>&1 | grep -v "^$" | head -5
  res=$(vvp -n $BUILD/$name.out | grep -E "^(PASS|FAIL)" | head -1)
  echo "$name: ${res:-NO RESULT}"
  case "$res" in PASS*) pass=$((pass+1)) ;; *) fail=$((fail+1)); failed+=($name) ;; esac
done

echo "passed $pass, failed $fail"
[ $fail -eq 0 ]
