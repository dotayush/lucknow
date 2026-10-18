#!/bin/bash
# screen.sh <new_dir> [src_dir]   quick look at an RTL change: synthesize l0_core and report each path segment with
# ideal wires (no place and route, about a minute). src_dir holds the l0 sources, default ../src. Compare two RTL
# versions by running it on both (git checkout-index into a directory for the old one). Ideal-wire numbers are
# about 1.3x too optimistic against routed wires (TIMING.md); a change is only worth a full run if it moves a segment more than that.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../../../eda/env.sh"
dir=$1; src=$(readlink -f "${2:-$HERE/../src}")
mkdir "$dir"; cd "$dir"
python3 - "$src" <<'PY'
import json,sys
src=sys.argv[1]
files=['shared','alu','csrfile','decoder','regfile','signext','control']
json.dump({"DESIGN_NAME":"l0_core","VERILOG_FILES":[f"{src}/{f}.sv" for f in files],"CLOCK_PORT":"clk","CLOCK_PERIOD":44,
  "EXTRA_EXCLUDED_CELLS":["sky130_fd_sc_hd__clkdlybuf*","sky130_fd_sc_hd__dlymetal*"],"DEFAULT_CORNER":"nom_ss_100C_1v60"},open("config.json","w"),indent=1)
PY
librelane --pdk-root "$LIBRELANE_PDK_ROOT" --pdk sky130A --run-tag s --to Yosys.Synthesis config.json > run.log 2>&1
R=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd
nl=$(ls runs/s/*yosys-synthesis/l0_core.nl.v)
cat > seg.tcl <<TCL
read_lef $R/techlef/sky130_fd_sc_hd__nom.tlef
read_lef $R/lef/sky130_fd_sc_hd.lef
read_liberty $R/lib/sky130_fd_sc_hd__ss_100C_1v60.lib
read_verilog $nl
link_design l0_core
create_clock -name clk -period 100 [get_ports clk]
set_input_delay 0 -clock clk [all_inputs -no_clocks]
set_output_delay 0 -clock clk [all_outputs]
set R [all_registers -clock_pins]
set D [all_registers -data_pins -edge_triggered]
set A {dmem_addr* dmem_wdata* dmem_size* dmem_read dmem_write}
proc seg {name from to} {
  foreach p [find_timing_paths -path_delay max -from \$from -to \$to -group_path_count 1 -sort_by_slack] {
    puts [format "%-36s %6.2f ns" \$name [expr [\$p data_arrival_time]*1e9]]
  }
}
seg "pc -> imem_addr" \$R [get_ports imem_addr*]
seg "imem_data -> dmem_addr/ctl/wdata" [get_ports imem_data*] [get_ports \$A]
seg "imem_data -> flops" [get_ports imem_data*] \$D
seg "dmem_rdata -> flops" [get_ports dmem_rdata*] \$D
seg "dmem_err -> flops" [get_ports dmem_err*] \$D
seg "flops -> dmem_addr/ctl/wdata" \$R [get_ports \$A]
seg "flops -> flops" \$R \$D
exit
TCL
echo "synthesis netlist, ideal wires, slow corner, $src"
openroad -no_splash -exit seg.tcl 2>&1 | grep " ns$"
