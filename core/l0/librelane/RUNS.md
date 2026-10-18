# l0_core LibreLane runs

One row per try that finished or taught something: settings, results, outcome. The model behind the numbers is in
`TIMING.md`. `results/t<N>.metrics.json` is the flow's final `metrics.json` for each finished run. Run folders are
about 1.8 GB each, live under `$EDA/scratch/l0-try<N>/runs/t<N>`, are linked as `runs/t<N>` while they exist,
and are deleted once recorded here (`run.sh` starts a run, `segments.sh` measures one, `screen.sh` previews an RTL change).

Common to every run: design `l0_core`, sky130A, `sky130_fd_sc_hd`, LibreLane 3.0.16, full flow, flip-flops 1408
(register file 1024, 11 CSRs 352, pc 32). `FP_CORE_UTIL` 40 and `PL_TARGET_DENSITY_PCT` 50 unless stated; die 254,154 um2
(about 504 um square). Slack is setup slack at signoff on extracted wires; `ss` is `max_ss_100C_1v60`, `tt` is
`nom_tt_025C_1v80`. Cell area is placed standard cells including taps, repair and clock buffers. Signoff = Magic DRC,
KLayout DRC, routing DRC, LVS, antenna and layout XOR; "clean" means all six are 0. Hold violations are 0 in every finished run.

## Settings

| try | question | change from the previous row | clock (ns) | optimized corner | constraints |
|---|---|---|---|---|---|
| t3 | does the trimmed core build | CSR file trimmed to 11 registers | 50 | tt | fallback SDC |
| t4 | do delay cells cost timing | `EXTRA_EXCLUDED_CELLS`: `clkdlybuf*`, `dlymetal*` | 50 | tt | fallback SDC |
| t5 | does the optimized corner matter | slow corner | 50 | ss | fallback SDC |
| t6 | does a tighter clock help | clock 38 | 38 | ss | fallback SDC |
| t7 | is the wire layer estimate the gap | `SIGNAL_WIRE_RC_LAYERS` met1, met2 | 38 | ss | fallback SDC |
| t8 | how far does the resizer go | clock 29 | 29 | ss | fallback SDC |
| t9 | does a setup margin close it | clock 36, setup margins 7 ns | 36 | ss | fallback SDC |
| t11 | which block owns the path | `SYNTH_HIERARCHY_MODE: keep`, `ERROR_ON_UNMAPPED_CELLS: false` | 36 | ss | fallback SDC |
| t14 | realistic constraints | `l0.sdc` (memory 4 ns, budgets 6 and 10 ns), default margins | 44 | ss | `l0.sdc` |
| t16 | does shorter wiring help | t14 plus `FP_CORE_UTIL` 55, density 65 | 44 | ss | `l0.sdc` |
| t17 | where do the hold buffers come from | t14 repeated | 44 | ss | `l0.sdc` |
| t18 | does splitting the trap help | RTL: trap split into early and late parts, t17 settings | 44 | ss | `l0.sdc` |
| t19 | does a dedicated address adder help | RTL: `rs1 + imm` for loads, stores and `jalr` on its own adder, t18 settings | 44 | ss | `l0.sdc` |

"Fallback SDC" is LibreLane's generic one: 20% of the clock as input and output delay on every port (`TIMING.md` section 2).
Not in the table: t1 (the core with memories inside, failed at floorplan: Yosys removed everything, `control` has no outputs),
t2 (4096-entry CSR array: 131,072 flops, stopped, Yosys too slow), t10 (failed in the unmapped-cell check on `$paramod`
module names), t12 and t13 (killed minutes in: parameter sweeps), t15 (`FP_CORE_UTIL` 65: `DPL-0036`, detailed placement ran
out of legal sites after the resizer added about 35% cell area).

## Results

| try | cell area (um2) | util | slack ss (ns) | slack tt (ns) | slack ff (ns) | violating paths | hold buffers | power (mW) | signoff | outcome |
|---|---|---|---|---|---|---|---|---|---|---|
| t3 | 135,683 | 0.57 | -10.22 | +11.20 | +17.34 | 4113 | 1312 | 2.76 | clean | first complete run |
| t4 | 129,116 | 0.54 | -8.31 | +13.06 | +18.58 | 3844 | 1315 | 2.76 | clean | area -5%, ss +1.9 ns |
| t5 | 129,074 | 0.54 | -7.91 | +13.13 | +18.64 | 3799 | 1315 | 2.76 | clean | corner did not matter |
| t6 | 129,234 | 0.54 | -8.17 | +8.62 | +13.25 | 4106 | 1315 | 3.64 | clean | tighter clock, same miss |
| t7 | 129,219 | 0.54 | -8.02 | +8.75 | +13.35 | 4106 | 1315 | 3.63 | clean | wire layer was not the cause |
| t8 | 133,320 | 0.56 | -7.36 | +5.61 | +9.48 | 4137 | 1315 | 4.78 | clean | resizer pushed hard, +3% area |
| t9 | 131,808 | 0.56 | -3.89 | +9.83 | +13.65 | 2592 | 1315 | 3.85 | clean | margin helped |
| t11 | 132,989 | - | -2.74 | +10.02 | +13.78 | 2878 | 1360 | 3.78 | clean | critical endpoint is in `csrfile_inst` |
| t14 | 120,960 | 0.51 | -4.43 | +3.62 | +4.25 | 331 | 1277 | 2.96 | clean | first run with real constraints |
| t16 | 119,304 | 0.69 | -5.67 | +3.67 | +4.25 | 1066 | 1286 | 2.87 | clean | die 186,915 um2 (-26%), wires -8%, slack 1.2 ns worse |
| t17 | 120,960 | 0.51 | -4.43 | +3.62 | +4.25 | 331 | 1277 | 2.96 | clean | bit-identical to t14: the flow is deterministic |
| t18 | 119,130 | - | -4.57 | +3.46 | +4.13 | 78 | 1302 | 2.96 | clean | targeted segments -6.5 ns, limiter is elsewhere |
| t19 | 121,800 | 0.51 | -2.38 | +3.79 | +4.37 | 20 | 1321 | 2.99 | clean | limiting segment -2.2 ns, area +2.2% |

Path segments, slow corner, extracted wires, no I/O delays (`segments.sh`):

| try | pc to `imem_addr` | `imem_data` to `dmem_addr` | `imem_data` to flop | `dmem_rdata` to flop | flop to `dmem_addr` | flop to flop |
|---|---|---|---|---|---|---|
| t9 | 4.8 | 21.4 | 32.6 | 9.5 | 16.9 | 27.8 |
| t11 | 3.5 | 20.9 | 31.6 | 9.0 | 15.4 | 26.3 |
| t14 = t17 | 3.3 | 23.7 | 35.8 | 6.8 | 19.5 | 31.7 |
| t16 | 3.2 | 25.0 | 36.4 | 6.1 | 19.1 | 30.6 |
| t18 | 3.6 | 23.6 | 29.3 | 6.8 | 17.6 | 23.0 |
| t19 | 3.0 | 21.4 | 30.1 | 6.6 | 15.5 | 24.8 |

## What was learned

1. **The flow's default I/O constraint hides the real path.** It puts 20% of the clock on every memory input. Without it the t9 path
   has slack. `l0.sdc` models the memory as an access time and cuts the cycle at the ports.
2. **The wire estimate during place and route is about 9 ns too optimistic on the worst path** (cells 23.6 ns, PnR estimate 24.7 ns,
   extracted 32.6 ns, from t9). Moving the optimized corner (t5), the clock (t6, t8), the wire layer (t7) or the fill (t16) did not close it.
3. **A flat 4096-entry CSR array is not buildable** (t2) and 11 named CSRs pass riscv-tests; the same applies to FPGA (`../fpga/FPGA.md`).
4. **Banning slow delay cells as buffers** gave 5% less area and about 2 ns (t4). Kept in `config.json`.
5. **The longest path under the fallback SDC ended in the CSR file** (t11, hierarchy kept): decode 2.4 ns, register read 7.7, ALU 8.4,
   control selection 5.9, buffers 3.8, CSR mux 4.9 = 31.6 ns.
6. **Splitting the trap into an early part and a late branch-only part took 6.5 ns off `imem_data` to flop and 8.7 ns off flop to flop** (t18),
   matching the ideal-wire preview (`screen.sh`) exactly. It does not move signoff slack at 44 ns, because under `l0.sdc` the limiting path is
   the cycle through memory twice, whose biggest piece, `imem_data` to `dmem_addr` (decode, register read, ALU add) at 23.6 ns, is untouched.
7. **A dedicated `rs1 + imm` adder** for loads, stores and `jalr` (t19) took 2.2 ns off `imem_data` to `dmem_addr` (preview 2.1 ns ideal, predicted 2.7 with wires),
   moved signoff slack at 44 ns from -4.57 to -2.38 ns and violating paths from 78 to 20, for +2.2% cell area. `imem_data` to flop and flop to flop got 0.8 and 1.8 ns
   worse in the routed result while the ideal-wire preview had them better: placement differences of about 1 to 2 ns are not predicted by the preview.
   The limiting path is still `imem_data` to `dmem_addr`, and its slack falls about 0.5 ns per address bit (bit 31 -2.38, bit 30 -1.91, bit 29 -1.39 ns): a carry chain that is
   close to ripple. Synthesis only has to meet the 44 ns target, so the adder it builds is the one that just meets it (item 2 of the next candidates).
8. **Hold buffers are a margin artifact** (t17, reports before repair). 1271 of the 1277 sit between a flop output and a mux input on the
   register-file and CSR hold loops, which do not violate: worst hold slack before repair is +0.062 ns (fast corner), +0.70 ns on a sample slow-corner loop.
   The repair tops each up to the 0.10 ns margin (`PL_RESIZER_HOLD_SLACK_MARGIN`, over 0.25 ns clock uncertainty). A policy question for a
   real chip; irrelevant for an FPGA.
9. **`l0.sdc` gave `rst_n` an input delay of 0** against a clock that reaches the flops 1.13 ns late: 403 removal violations before repair (worst -1.59 ns),
   all `rst_n` to a flop reset pin. A fair constraint gives the reset the host's registered release time. Not changed, so t14 to t18 stay comparable.
10. **Fill is not the timing lever** (t16): 55% fill gave a die 26% smaller and wires 8% shorter, and slack 1.2 ns worse. 65% does not place (t15).
11. **A hard target costs time**: the post-clock-tree timing repair was 40 of t9's 56 minutes. With `l0.sdc` it is short. Synthesis through clock tree is
    about 2 minutes; signoff checks (stream-out, DRC, LVS, XOR) about 3.5.
12. **The layout is manufacturable** in every finished run. Only slow-corner timing is open.

## Next candidates

- The adder structure on the limiting segment. Synthesis and the resizer stop once the 44 ns target is met, so the carry chain is whatever just meets it
  (slack drops about 0.5 ns per bit toward bit 31). `SYNTH_ADDER_TYPE` (`YOSYS` default, `FA`, `RCA`, `CSA`) and a tighter synthesis target are the levers; the
  question to answer first is how deep the adder is in the synthesized netlist (`screen.sh`), not which setting is faster.
- Fix the `rst_n` input delay in `l0.sdc` (item 9).

## Reproducing

`run.sh` fills in the slow corner, the delay cell exclusions and `l0.sdc` from the PDK in `.env`. Tries t3 to t11 used the flow's fallback SDC; `run.sh` no longer starts such a run.

```bash
core/l0/librelane/screen.sh <new_dir>                 # preview an RTL change, about a minute
core/l0/librelane/run.sh t<N> '{"CLOCK_PERIOD": 44}'   # slow corner, delay cells and l0.sdc come from run.sh and .env (PDK_FAMILY)
core/l0/librelane/segments.sh core/l0/librelane/runs/t<N>/final
```
