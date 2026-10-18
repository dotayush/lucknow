# Constraints for l0_core. The core has no memory inside: a cycle goes
#   pc -> imem_addr -> [memory] -> imem_data -> decode, register read, alu -> dmem_addr -> [memory] -> dmem_rdata -> flop
# so the memory's access time is part of the clock period. STA cannot follow a path through an external
# memory, so the cycle is cut at the ports and each piece gets a budget that adds up to the period.
# Replaces LibreLane's generic fallback (20% of the period on every input and output).
#
# budgets in ns (assumptions, change them when the real memory is known):
set T_MEM     4.0   ;# memory access time, address in to data out, wires included
set B_PC_OUT  6.0   ;# pc flop -> imem_addr      (measured 4.8 on t9, slow corner)
set B_LOAD    10.0  ;# dmem_rdata -> flop        (measured 9.5 on t9)
#
# what each port constraint then means (T = clock period):
#   imem_data arrives B_PC_OUT + T_MEM after the clock edge
#   dmem_rdata arrives T - B_LOAD after the clock edge (the address path and the memory used the rest)
#   every output has to reach its memory in time: imem_addr within T - B_PC_OUT,
#   dmem_* within T - (T_MEM + B_LOAD)
# so imem_data -> dmem_addr (decode, regfile, alu) gets T - (B_PC_OUT + T_MEM) - (T_MEM + B_LOAD).

create_clock -name $::env(CLOCK_PORT) -period $::env(CLOCK_PERIOD) [get_ports $::env(CLOCK_PORT)]
set_clock_uncertainty 0.25 [get_clocks $::env(CLOCK_PORT)]
set_clock_transition 0.15 [get_clocks $::env(CLOCK_PORT)]

set clk [get_clocks $::env(CLOCK_PORT)]
set T $::env(CLOCK_PERIOD)

set_input_delay -clock $clk [expr {$B_PC_OUT + $T_MEM}] [get_ports {imem_data* imem_err*}]
set_input_delay -clock $clk [expr {$T - $B_LOAD}] [get_ports {dmem_rdata* dmem_err*}]
set_input_delay -clock $clk 0 [get_ports rst_n]

set_output_delay -clock $clk [expr {$T - $B_PC_OUT}] [get_ports {imem_addr*}]
set_output_delay -clock $clk [expr {$T_MEM + $B_LOAD}] [get_ports {dmem_addr* dmem_wdata* dmem_size* dmem_read dmem_write}]

set_driving_cell -lib_cell $::env(PDK_DRIVING_CELL) -pin Y [all_inputs -no_clocks]
set_load 0.05 [all_outputs]

# dmem_rdata also reaches dmem_wdata structurally (the load result and the store data share one sign extender,
# control.sv unextended_data2). a load never writes memory and dmem_wdata is only used when dmem_write is 1,
# so that path can never be exercised.
set_false_path -from [get_ports {dmem_rdata*}] -to [get_ports {dmem_wdata*}]
