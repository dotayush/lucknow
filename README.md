### unknown.

a risc-v core with a 32-bit instruction set implementing
the rv32i specification written in verilog.

### features.

- minimalisitic core.
- single cycle instruction execution.

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
