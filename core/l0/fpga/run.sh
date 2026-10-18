#!/bin/bash
# run.sh <new_dir> [25k|45k|85k]   FPGA view of l0_core: LUT count and a fmax estimate on a Lattice ECP5.
# yosys with the slang front end (the built-in one drops `import isa_shared::*` and gives wrong counts),
# then nextpnr-ecp5 with no pin constraints, so only the logic and routing are measured.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../../../eda/env.sh"
S=$HERE/../src
dir=$1; dev=${2:-25k}
mkdir "$dir"; cd "$dir"
cat > synth.ys <<YS
plugin -i slang
read_slang --top l0_core $S/shared.sv $S/alu.sv $S/csrfile.sv $S/decoder.sv $S/regfile.sv $S/signext.sv $S/control.sv
synth_ecp5 -top l0_core -json l0.json
tee -o stat.txt stat
YS
yosys -q -l synth.log synth.ys
: > empty.lpf
nextpnr-ecp5 --$dev --package CABGA381 --speed 6 --json l0.json --lpf empty.lpf --lpf-allow-unconstrained --freq 30 --seed 1 --log pnr.log > /dev/null 2>&1 || true
grep -E "^\s+[0-9]+\s+(TRELLIS_FF|LUT4|L6MUX21|PFUMX|TRELLIS_DPR16X4|DP16KD|CCU2C)" stat.txt
grep -E "TRELLIS_COMB:|TRELLIS_FF:|DP16KD:|TRELLIS_IO:" pnr.log | tail -4
grep -E "Max frequency|Max delay" pnr.log | tail -4
