### unknown.

a risc-v core with a 32-bit instruction set implementing
the rv32i specification written in verilog.

### features.

- minimalisitic core.
- single cycle instruction execution.

### iverilog compile & simulation via oss-cad-suite.

```bash

# single module compilation (for example: alu.sv)
iverilog -g2012 -o ./tests/results/test_alu.out ./src/shared.sv ./src/alu.sv ./tests/test_alu.sv
vvp ./tests/results/test_alu.out # generates a ./tests/results/test_alu.vcd file for gtkwave visualization

# top module compilation (for example: control.sv)
iverilog -g2012 -o ./tests/results/test_control.out -c compile.f # compile.f ensures order of compilation is maintained
vvp ./tests/results/test_control.out # generates a ./tests/results/test_control.vcd file for gtkwave visualization
```

### yosys processing.

```bash
# start yosys
yosys

# inside yosys terminal
read -sv ./src/*.sv
hierarchy -check -top control
proc # convert design to strcutural repr.

# visualization processing
write_json control_design.json # write a json netlist (processing by other tools)
show -format dot -prefix control_design # write a dot for graphviz
```

### post processing.

```bash
# if you've generated the dot file, you can visualize it with graphviz
dot -Tsvg control_design.dot -o control_design_dot.svg

# if you've generated a json file, i suggest you to use the pp_json.py
# first to simplify the module naming before using it with other visualization tools
python pp_json.py
netlistsvg control_design.json -o control_design.svg # example of json netlist usage with another visualization tool
```

### license.

       ╱|、
     (˚ˎ 。7
      |、˜〵
     じしˍ,)ノ

the repository and everything within is licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.en.html).
Refer to [COPYING.md](./COPYING.md) for the full license text.
