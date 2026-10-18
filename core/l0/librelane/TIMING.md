# l0_core timing: what sets the clock and why

The model behind the timing numbers in `RUNS.md`. Numbers are slow corner (`ss`, 100 C, 1.60 V) with wires extracted from the
routed layout unless stated. Anything marked *assumption* or *estimate* has not been measured.

There is no target clock. l0 and k0 are not being optimized for a shuttle (no I/O, die area or clock requirement applies), and
k0 is headed for an FPGA first. The clock figures here are what the structure costs, used to find deficiencies.

## 1. The cycle

`l0_core` has no memory inside. One instruction takes one clock, and the cycle goes through the outside memory twice:

```
pc flop -> imem_addr --[memory]--> imem_data -> decode -> register read -> ALU -> dmem_addr --[memory]--> dmem_rdata -> load align -> flop
```

So the clock period T has to cover

    T >= t_pc_out + T_mem + t_exec + T_mem + t_load

where `t_pc_out` is pc to `imem_addr`, `t_exec` is `imem_data` to `dmem_addr` (decode, register read, ALU), `t_load` is
`dmem_rdata` to a flop, and `T_mem` is the access time of whatever memory the host design puts there.
STA cannot follow a path through an external memory. `l0.sdc` cuts the cycle at the ports and gives each piece a
budget (`T_MEM`, `B_PC_OUT`, `B_LOAD`) so the pieces add up to T.

**`T_mem` and the budgets are assumptions** (4, 6 and 10 ns) until a real memory is chosen. A different `T_mem`
changes the answer by 2 ns per ns, because the memory is in the chain twice.

## 2. Flow pitfalls found (details in `RUNS.md`)

1. **The flow's default I/O constraint.** Without an SDC, LibreLane puts an input delay of 20% of the clock on every input. The failing
   path starts at a memory input, so about 20% of T was a placeholder that scales with T, and tightening T never closed it.
2. **A path that is not real.** `dmem_rdata` reaches `dmem_wdata` structurally (the load result and the store data share one sign extender,
   `unextended_data2`). A load never writes memory, so `l0.sdc` marks that path false.
3. **The wire estimate during place and route is about 9 ns too optimistic** on the worst path (same layout, no I/O delay):

   | wire model | `imem_data` to flop |
   |---|---|
   | none (cells only) | 23.6 ns |
   | the flow's estimate during PnR | 24.7 ns |
   | extracted from the routed layout | 32.6 ns |

   The resizer sees about 1 ns of it and stops early. The larger stage delays are weak `buf_1` fan-out buffers driving 0.07 to 0.12 pF
   (5 to 11 loads), 1.3 to 1.8 ns each. The optimized corner, the clock target, the wire layer and the fill did not change this.
   Remaining candidate, not tested: the fan-out itself, since decode and register-select signals each reach 1000 or more flops.
4. **Hold buffers** (about 10% of cell area) come from a 0.10 ns hold margin on loops that already pass; they are not a physical failure.
5. **`rst_n` has an input delay of 0 in `l0.sdc`**, which gives 403 spurious removal violations before repair.

## 3. Where the time goes inside the core

Worst `imem_data` to flop path under the fallback constraint (`t11`, hierarchy kept, so every cell carries its block name):

| stage | block | cells | time |
|---|---|---|---|
| instruction decode | `decoder_inst` | 5 | 2.4 ns |
| register read (two 32:1 muxes) | `regfile_inst` | 14 | 7.7 ns |
| ALU: add, compare, op select | `alu_inst` | 17 | 8.4 ns |
| operand select, branch taken, trap select, next pc | `control` | 10 | 5.9 ns |
| fan-out and wire buffers between blocks | | 13 | 3.8 ns |
| CSR input muxing: trap, `mret`, write | `csrfile_inst` | 10 | 4.9 ns |
| **total** | | | **31.6 ns** |

The register read and the ALU are structural: a 32-entry read mux per port and a 32-bit adder with operation select.
After them, everything is serial: `taken` from the ALU compare, then the trap choice, then what the register file and CSRs load.

Segments (`segments.sh`, slow corner, extracted wires, no I/O delays), before and after splitting the trap (`t17` to `t18`):

| segment | before | after |
|---|---|---|
| pc to `imem_addr` | 3.3 | 3.6 |
| `imem_data` to `dmem_addr`/ctl/`dmem_wdata` | 23.7 | 23.6 |
| `imem_data` to flop | 35.8 | **29.3** |
| `dmem_rdata` to flop | 6.8 | 6.8 |
| flop to `dmem_addr`/ctl/`dmem_wdata` | 19.5 | 17.6 |
| flop to flop | 31.7 | **23.0** |

Segment times are not a floor: the resizer stops once a constraint is met, so the same logic is slower under a looser target.

With `T_mem` = 4 ns the chain through memory twice is about 3.6 + 4 + 23.6 + 4 + 6.8 = 42 ns for `t18`'s layout. The limiting segment
under `l0.sdc` is `imem_data` to `dmem_addr`, which the trap split does not touch: signoff slack at 44 ns stayed at -4.6 ns.

## 4. What the trap split changed

Before, `trap` was the OR of five sources and fanned out to about 1,400 flops: the register-file write enable, every CSR write and
the `next_pc` mux. For a taken branch the late compare reached all of them. Now `control.sv` makes `trap_early` (fetch, decode, memory
errors, interrupts, misaligned jump or `mret` target) and a late part, `late_misaligned` (taken branch to a misaligned target). The register
file and the CSRs a trap does not touch use `trap_early` only, which is equivalent because a branch writes no register and no CSR. The late
part reaches `next_pc`, `mepc`, `mcause`, `mtval` and `mstatus`, as the last mux. `csrfile.sv` has a `trap_early` input for this. Same change in `soc/k0/core`.

## 5. What could change the clock next

1. **A dedicated address adder** (`rs1 + imm`) for loads and stores. They send it through the shared ALU, with its operand and
   op-select muxes in front and the result mux behind; the limiting segment is `imem_data` to `dmem_addr`. *Estimate* a few ns.
   *Check:* `screen.sh` before and after.
2. **Memory timing as a design input.** `T_mem` counts twice. A registered memory read removes the fetch from the chain; that needs a
   pipeline stage (l0 documents "no stall mechanism"), so it is a k0-level decision.
3. **Pipelining** (fetch | decode and register read | execute | memory and write-back) splits the register read and ALU across cycles, at the cost
   of hazards and forwarding. Not needed unless a clock target appears.

## 6. How to measure without brute force

- `./screen.sh <new_dir> [src_dir]` synthesizes `l0_core` and reports the segments with ideal wires in about a minute. Run it on the old RTL
  (`git checkout-index`) and the new one. The ideal-wire change of the trap split was -6.5 ns on `imem_data` to flop; the full run
  gave -6.5 ns. Only a change that moves a segment by more than the 1.3x wire factor is worth a full run.
- `./segments.sh runs/<tag>/final [corner]` reports the segments for a finished run in seconds. A new `T_MEM` or budget can be checked against an
  existing layout by editing `l0.sdc`; no new place and route is needed for a constraint change.
- Hierarchy-kept synthesis (`SYNTH_HIERARCHY_MODE: keep`, `ERROR_ON_UNMAPPED_CELLS: false`) gives block names on every cell, which made section 3 possible.

## 7. Open

- The real memory (and its access time) l0 will be paired with, and whether the budgets in `l0.sdc` match it.
- The wire gap (section 2, point 3), described but not fixed.

## 8. The open SRAM macros in the PDK, and why `l0.sdc` does not use their timing

`sky130_sram_macros` in the PDK holds OpenRAM macros: `sky130_sram_1kbyte_1rw1r_32x256_8` (480 x 398 um),
`sky130_sram_2kbyte_1rw1r_32x512_8` (683 x 417 um), `sky130_sram_1kbyte_1rw1r_8x1024_8` and the older
`sram_1rw1r_32_256_8_sky130`. The largest is 2 KiB. Nothing in the PDK comes close to the 16 MiB k0's Linux plan needs.

- **Interface.** The macros read synchronously: the address is captured on the rising edge (setup 0.10 ns) and `dout0`
  changes after the *falling* edge of the same clock (`timing_type: falling_edge`). So data is valid half a cycle plus
  about 0.4 ns after the capture edge. l0 reads memory combinationally in the same cycle, so a macro cannot be dropped
  in. A macro fits a core that drives the address from `next_pc` and registers the data, or that stalls (k0 has wait states).
- **Timing data.** Only the TT 25 C corner ships for the three newer macros: clock-to-`dout` 0.34 to 0.48 ns, minimum
  period 1.79 ns (32x256). OpenRAM's own build log for `sky130_sram_1kbyte_1rw1r_32x256_8` (in the
  VLSIDA/sky130_sram_macros repository) says "Characterization is disabled (using analytical delay models)
  (analytical_delay=False to simulate)" and "Only generating nominal corner timing", and its Elmore sample row
  contains 0.3386, the same 0.339 ns that is in the `.lib`. So those numbers are the output of an analytical
  model, not a SPICE characterization and not silicon. The config (`sky130_sram_common.py`) has
  `nominal_corner_only = True` and `analytical_delay` commented out. The macros have been taped out and OpenRAM
  reports first silicon verified (UCSC, ISCAS 2023), but no published access time or maximum clock was found for these
  macros; one Efabless user project that used 2 KB OpenRAM macros states a 50 MHz maximum, which is a system limit.
  The older `sram_1rw1r_32_256_8_sky130` has several corners that disagree with each other (FF/TT/SS 25 C: 0.40 to
  0.65 ns and minimum periods of 0.11 to 0.13 ns; TT 100 C: 5.9 to 7.8 ns); how those were generated was not found.
- **So `l0.sdc` keeps the abstract memory budget** (`T_MEM`, `B_PC_OUT`, `B_LOAD`). A sync macro needs a different constraint
  shape: clock-referenced input delay of T/2 + clock-to-`dout` for the data and the 0.10 ns setup as output delay on the
  address. That belongs with the k0 interface (wait states), when the memory plan for k0 is decided; on an FPGA the
  memory is block RAM or external SDRAM instead.
