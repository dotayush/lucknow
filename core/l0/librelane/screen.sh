#!/bin/bash
# screen.sh <new_dir> [src_dir]   quick look at an RTL change: synthesize l0_core and report each path segment with
# ideal wires (no place and route, about a minute). SCREEN_CFG='{"SYNTH_ADDER_TYPE":"RCA"}' adds flow settings.
# another design: SCREEN_TOP (module), SCREEN_FILES (space separated, in src_dir) and SCREEN_SEGS (a tcl file with the seg lines, see below).
# src_dir holds the l0 sources, default ../src. Compare two RTL
# versions by running it on both (git checkout-index into a directory for the old one). Ideal-wire numbers are
# about 1.3x too optimistic against routed wires (TIMING.md); a change is only worth a full run if it moves a segment more than that.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../../../eda.sh"
dir=$1; src=$(readlink -f "${2:-$HERE/../src}")
mkdir "$dir"; cd "$dir"
TOP=${SCREEN_TOP:-l0_core}
FILES=${SCREEN_FILES:-shared alu csrfile decoder regfile signext control}
python3 - "$src" "${SCREEN_CFG:-"{}"}" "$TOP" "$FILES" <<'PY'
import json,sys,os
src=sys.argv[1]; extra=json.loads(sys.argv[2]); top=sys.argv[3]; files=sys.argv[4].split()
cfg=({"DESIGN_NAME":top,"VERILOG_FILES":[f"{src}/{f}.sv" for f in files],"CLOCK_PORT":"clk","CLOCK_PERIOD":44,
  "EXTRA_EXCLUDED_CELLS":[os.environ["STD_CELL_LIBRARY"]+"__"+x for x in os.environ.get("PDK_DELAY_CELLS","").split(",") if x],
  "DEFAULT_CORNER":"nom_"+os.environ["PDK_SLOW"]}); cfg.update(extra); json.dump(cfg,open("config.json","w"),indent=1)
PY
librelane --pdk-root "$LIBRELANE_PDK_ROOT" --pdk "$PDK_DIGITAL" --run-tag s --to Yosys.Synthesis config.json > run.log 2>&1
nl=$(ls runs/s/*yosys-synthesis/$TOP.nl.v)
cat > seg.tcl <<TCL
read_lef $PDK_TECH_LEF
read_lef $PDK_CELL_LEF
read_liberty $PDK_LIB_SLOW
read_verilog $nl
link_design $TOP
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
if {"$SCREEN_SEGS" ne ""} { source $SCREEN_SEGS } else {
seg "pc -> imem_addr" \$R [get_ports imem_addr*]
seg "imem_data -> dmem_addr/ctl/wdata" [get_ports imem_data*] [get_ports \$A]
seg "imem_data -> flops" [get_ports imem_data*] \$D
seg "dmem_rdata -> flops" [get_ports dmem_rdata*] \$D
seg "dmem_err -> flops" [get_ports dmem_err*] \$D
seg "flops -> dmem_addr/ctl/wdata" \$R [get_ports \$A]
seg "flops -> flops" \$R \$D
}
exit
TCL
echo "synthesis netlist, ideal wires, slow corner, $src"
openroad -no_splash -exit seg.tcl 2>&1 | grep " ns$"
