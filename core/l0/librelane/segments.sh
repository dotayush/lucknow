#!/bin/bash
# segments.sh <run>/final [corner]   e.g. segments.sh runs/t9/final max_ss_100C_1v60   (default: max_ + the slow corner of the PDK in .env)
# the delay of each piece of the l0_core cycle, taken from a finished run: its database, the
# standard cell liberty of the corner and the extracted wires, with no input or output delays.
# a clock period has to cover  pc->imem_addr + memory + imem_data->dmem_addr + memory + dmem_rdata->flop.
# (the generic 20% I/O delay of the flow hides this, see RUNS.md.)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../../../eda.sh"
final=$(readlink -f "$1"); corner=${2:-max_$PDK_SLOW}
pvt=${corner#*_}; rc=${corner%%_*}
[ -d "$final/spef/$rc" ] || rc=nom   # a PDK with only nominal extraction rules (IHP)
tcl=$(mktemp "${TMPDIR:-/tmp}/segments-XXXXXX.tcl")
cat > "$tcl" <<TCL
read_liberty ${PDK_LIB_SLOW%$PDK_SLOW.lib}$pvt.lib
read_db $final/odb/l0_core.odb
create_clock -name clk -period 100 [get_ports clk]
set_propagated_clock [get_clocks clk]
set_input_delay 0 -clock clk [all_inputs -no_clocks]
set_output_delay 0 -clock clk [all_outputs]
read_spef $final/spef/$rc/l0_core.$rc.spef
set R [all_registers -clock_pins]
set D [all_registers -data_pins -edge_triggered]
set A {dmem_addr* dmem_wdata* dmem_size* dmem_read dmem_write}
proc seg {name from to} {
  foreach p [find_timing_paths -path_delay max -from \$from -to \$to -group_path_count 1 -sort_by_slack] {
    puts [format "%-36s %6.2f ns  (ends at %s)" \$name [expr [\$p data_arrival_time]*1e9] [get_full_name [\$p pin]]]
  }
}
seg "pc -> imem_addr" \$R [get_ports imem_addr*]
seg "imem_data -> dmem_addr/ctl/wdata" [get_ports imem_data*] [get_ports \$A]
seg "imem_data -> flops" [get_ports imem_data*] \$D
seg "dmem_rdata -> flops" [get_ports dmem_rdata*] \$D
seg "flops -> dmem_addr/ctl/wdata" \$R [get_ports \$A]
seg "flops -> flops" \$R \$D
exit
TCL
echo "corner $corner, $final"
openroad -no_splash -exit "$tcl" 2>&1 | grep -E " ns  |Error"
rm "$tcl"
