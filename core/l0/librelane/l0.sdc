# Constraints for l0_core. The core has no memory inside: a cycle goes
#   pc -> imem_addr -> [memory] -> imem_data -> decode, register read, alu -> dmem_addr -> [memory] -> dmem_rdata -> flop
# so the memory's access time is part of the clock period. STA cannot follow a path through an external
# memory, so the cycle is cut at the ports and each piece gets a budget that adds up to the period.
# Replaces LibreLane's generic fallback (20% of the period on every input and output).
#
# budgets in ns of sky130 hd at its slow corner (assumptions, change them when the real memory is known). On another PDK they
# are scaled by the ratio of the FO4 delays (PDK_FO4_PS, fo4.sh), so every PDK gets the same budget in gate delays:
set S [expr {$::env(PDK_FO4_PS) / 131.3}]
set T_MEM     [expr {4.0 * $S}]   ;# memory access time, address in to data out, wires included
set B_PC_OUT  [expr {4.25 * $S}]  ;# pc flop -> imem_addr      (3.2 ns routed on t32 plus driver, port load and uncertainty; 4.0 fails by 0.13, t30)
set B_LOAD    [expr {10.0 * $S}]  ;# dmem_rdata, dmem_err -> flop (dmem_err through the trap tree needs about 10; 9.0 fails by 1.0, t28)
#
# what each port constraint then means (T = clock period):
#   imem_data arrives B_PC_OUT + T_MEM after the clock edge
#   dmem_rdata arrives T - B_LOAD after the clock edge (the address path and the memory used the rest)
#   every output has to reach its memory in time: imem_addr within T - B_PC_OUT,
#   dmem_* within T - (T_MEM + B_LOAD)
# so imem_data -> dmem_addr (decode, regfile, alu) gets T - (B_PC_OUT + T_MEM) - (T_MEM + B_LOAD).

create_clock -name $::env(CLOCK_PORT) -period $::env(CLOCK_PERIOD) [get_ports $::env(CLOCK_PORT)]
set_clock_uncertainty [expr {0.25 * $S}] [get_clocks $::env(CLOCK_PORT)]
set_clock_transition [expr {0.15 * $S}] [get_clocks $::env(CLOCK_PORT)]

set clk [get_clocks $::env(CLOCK_PORT)]
set T $::env(CLOCK_PERIOD)

set_input_delay -clock $clk [expr {$B_PC_OUT + $T_MEM}] [get_ports {imem_data* imem_err*}]
set_input_delay -clock $clk [expr {$T - $B_LOAD}] [get_ports {dmem_rdata* dmem_err*}]
set_input_delay -clock $clk [expr {1.5 * $S}] [get_ports rst_n]   ;# the host releases reset from a flop of its own (t14 to t26 used 0 and had removal violations)

set_output_delay -clock $clk [expr {$T - $B_PC_OUT}] [get_ports {imem_addr*}]
set_output_delay -clock $clk [expr {$T_MEM + $B_LOAD}] [get_ports {dmem_addr* dmem_wdata* dmem_size* dmem_read dmem_write}]

set_driving_cell -lib_cell $::env(PDK_DRIVING_CELL) -pin $::env(PDK_DRIVING_PIN) [all_inputs -no_clocks]
set_load 0.05 [all_outputs]

# dmem_rdata also reaches dmem_wdata structurally (the load result and the store data share one sign extender,
# control.sv unextended_data2). a load never writes memory and dmem_wdata is only used when dmem_write is 1,
# so that path can never be exercised.
set_false_path -from [get_ports {dmem_rdata*}] -to [get_ports {dmem_wdata*}]
