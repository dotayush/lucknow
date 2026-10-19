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

| segment | `t17` before | `t18` after the trap split | `t19` after the address adder | `t20` decode out of the register read |
|---|---|---|---|---|
| pc to `imem_addr` | 3.3 | 3.6 | 3.0 | 3.2 |
| `imem_data` to `dmem_addr`/ctl/`dmem_wdata` | 23.7 | 23.6 | 21.4 | **18.9** |
| `imem_data` to flop | 35.8 | **29.3** | 30.1 | 28.3 |
| `dmem_rdata` to flop | 6.8 | 6.8 | 6.6 | 8.0 |
| flop to `dmem_addr`/ctl/`dmem_wdata` | 19.5 | 17.6 | 15.5 | 16.5 |
| flop to flop | 31.7 | **23.0** | 24.8 | 25.8 |

Segment times are not a floor: the resizer stops once a constraint is met, so the same logic is slower under a looser target.

With `T_mem` = 4 ns the chain through memory twice is about 3.0 + 4 + 21.4 + 4 + 6.6 = 39 ns for `t19`'s layout. The limiting segment
under `l0.sdc` is `imem_data` to `dmem_addr`: the trap split did not touch it (signoff slack at 44 ns stayed at -4.6 ns), the address adder
took 2.2 ns off it (-2.4 ns). `t20` took the decoder out of the register read: the register file used to read the decoder's `rs1`/`rs2`, which are zeroed for
instructions that do not use them, so a decode net with fanout 134 (4 ns) sat in front of the read mux. It now reads the instruction fields directly,
which took `imem_data` to `dmem_addr` to 18.9 ns and the signoff slack to -0.01 ns (one path). The chain is then 3.2 + 4 + 18.9 + 4 + 8.0 = 38 ns.

## 4. What the trap split changed

Before, `trap` was the OR of five sources and fanned out to about 1,400 flops: the register-file write enable, every CSR write and
the `next_pc` mux. For a taken branch the late compare reached all of them. Now `control.sv` makes `trap_early` (fetch, decode, memory
errors, interrupts, misaligned jump or `mret` target) and a late part, `late_misaligned` (taken branch to a misaligned target). The register
file and the CSRs a trap does not touch use `trap_early` only, which is equivalent because a branch writes no register and no CSR. The late
part reaches `next_pc`, `mepc`, `mcause`, `mtval` and `mstatus`, as the last mux. `csrfile.sv` has a `trap_early` input for this. Same change in `soc/k0/core`.

## 5. What could change the clock next

Done: the trap split (section 4) and the dedicated address adder. Loads, stores and `jalr` used to send `rs1 + imm` through the shared ALU,
with its operand and op-select muxes in front and the result mux behind; it now has its own adder (`addr_sum` in `control.sv`).

1. **Anything between the instruction and the register read or the operand muxes that does not have to be there** (found in `t20`: gated `rs1`).
   The adder structure is not the lever: `SYNTH_ADDER_TYPE` `YOSYS` and `FA` give the same netlist and `CSA` and `RCA` are slower (`RUNS.md` item 8).
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

## 6. The same design on three PDKs

One full flow per PDK, same RTL (the `t20` core), same flow, same `l0.sdc` structure, judged at each PDK's slowest corner with the largest wire RC
(sky130 `max_ss_100C_1v60`, gf180mcu `max_ss_125C_4v50`; IHP only has nominal extraction rules, so `nom_slow_1p08V_125C`).
The ns in `l0.sdc` (memory 4 ns, budgets 6 and 10 ns, uncertainty 0.25 ns) and the clock target are scaled by the PDK's FO4 delay, so each PDK gets the same budget in gate delays:
the first IHP run with unscaled budgets (25 ns, 107 violating paths, -5.9 ns) only showed that the sky130 nanoseconds do not carry over.

FO4 = the delay of an inverter driving four inverters, from the liberty file at the slow corner (`fo4.sh`, ideal wires, `inv_1`):

| | sky130 hd (t20) | IHP SG13G2 (t24) | gf180mcu 7t 5V (t25) |
|---|---|---|---|
| slow corner | ss 100C 1.6 V | slow 125C 1.08 V | ss 125C 4.5 V |
| FO4 slow / typical | 131 / 77 ps | 99 / 65 ps | 414 / 236 ps |
| clock target | 44.0 ns | 33.1 ns | 138.8 ns |
| slack at the slow corner | -0.01 ns | +1.10 ns | +2.78 ns |
| **period needed, slow corner** | **44.0 ns** (22.7 MHz) | **32.0 ns** (31.3 MHz) | **136.0 ns** (7.4 MHz) |
| ... in FO4 | 335 | 324 | 329 |
| ... relative to sky130 | 1.00 | 0.73 | 3.09 |
| period needed, typical corner | 40.4 ns (24.7 MHz) | 30.0 ns (33.3 MHz) | 126.1 ns (7.9 MHz) |
| standard cell area | 122,226 um2 | 185,254 um2 | 371,327 um2 |
| ... in NAND2 equivalents (min NAND2: 3.75 / 7.26 / 10.98 um2) | 32,562 | 25,526 | 33,831 |
| signoff (DRC, LVS, antenna) | clean | clean | LVS and Magic DRC clean; KLayout DRC not reported |

Segments, extracted wires, no I/O delays (`segments.sh`), in ns and in FO4:

| segment | sky130 | IHP | gf180mcu |
|---|---|---|---|
| `pc` to `imem_addr` | 3.2 (24) | 1.7 (17) | 9.1 (22) |
| `imem_data` to `dmem_addr` | 18.9 (144) | 11.0 (111) | 47.2 (114) |
| `imem_data` to flop | 28.3 (216) | 17.9 (181) | 71.8 (173) |
| `dmem_rdata` to flop | 8.0 (61) | 5.3 (54) | 21.5 (52) |
| flop to `dmem_addr` | 16.5 (126) | 7.8 (79) | 34.0 (82) |
| flop to flop | 25.8 (196) | 14.7 (149) | 54.8 (132) |

What this says:
- **Gate speed is the first-order difference.** The same netlist needs 324 to 335 FO4 on all three; the period differs by the FO4 delay: IHP 0.73 of sky130, gf180mcu 3.1 times.
  This is partly by construction (the targets were scaled by FO4 and the two non-sky130 runs closed with slack), so the per-segment FO4 counts say more than the period does.
- **Sky130's segments are the deepest in FO4** (address path 144 against 111 and 114). sky130 was run to zero slack, so its resizer worked on the whole design to hit 44 ns;
  IHP and gf180mcu closed with slack and were not pushed. Segment times are therefore not floors (item at the top of section 3).
- **Fewer FO4 per segment on the two other libraries is not a faster architecture**: it may be the libraries (sizes and drive strengths on offer) and the slack they closed with; this run cannot separate the two.
- **Area**: in NAND2 equivalents the three are within 25% of each other (IHP 0.78, gf180mcu 1.04 of sky130), so the die size differences are the cell sizes.
- **IHP** is a BiCMOS process for analog and RF; its digital library is a secondary offering, so treat it as a 130 nm class CMOS data point, not as the digital reference.
- gf180mcu is a 5 V process: it is 3.1 times slower per period, and the KLayout DRC step did not report for it.
- Not covered: power (different supplies), clock tree differences, wires from a tuned flow per PDK. A shorter target per PDK would show the true minimum period.

The metrics of the three runs are in `results/t20.metrics.json`, `results/t24.metrics.json` and `results/t25.metrics.json` (the run folders are deleted).
