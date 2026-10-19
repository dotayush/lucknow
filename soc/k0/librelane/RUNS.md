# k0 synthesis and timing previews

The k0 core is the module `control` (`soc/k0/core`: `shared signext alu decoder regfile csrfile pmp control`); the bus, clint, plic, uart and cache are not part of it, like in
`core/l0/librelane/RUNS.md`, which has the l0 flow and the method. Previews are `core/l0/librelane/screen.sh` with `SCREEN_TOP=control`, `SCREEN_FILES` and
`SCREEN_SEGS=soc/k0/librelane/segs.tcl`: Yosys and ABC with the PDK's slow corner, ideal wires, inputs at time 0. A preview is not a try: tries will be `k0-try<N>`, tag `t<N>`,
listed here when the first full LibreLane run is made.

## Previews

| # | what | ABC script (`SYNTH_STRATEGY`) | result |
|---|---|---|---|
| P1 | k0 as it was: three 64x64 multiplies and four 32 bit dividers, one per instruction | `AREA 0` (default) | **did not finish**: ABC mapping step running after 40 minutes, stopped |
| P2 | P1 with the multiplies and divides replaced by constants | `AREA 0` | finished; `imem_data` to memory 29.4 ns, `imem_data` to flop 37.0, flop to flop 36.8 |
| P3 | one 33 bit multiplier and one unsigned divider shared by the four operations of each | `AREA 0` | **did not finish**: ABC mapping step running after 35 minutes, stopped |
| P4 | P3 | `AREA 3` | finished in about 1.5 minutes: 82.7 / 84.3 / 83.7 ns (table below) |
| P5 | P4 with the divider replaced by constants | `AREA 3` | 15.9 / 17.1 / 17.8 ns |
| P6 | l0 for comparison | `AREA 3` | 6.0 / 7.8 / 7.7 ns (`AREA 0`: 11.4 / 19.2 / 17.8) |
| P7 | multi-cycle divider (`core/divider.sv`, 34 clocks per divide, held by `stall`) | `AREA 3` | 14.7 / 16.8 / 17.5 ns |
| P8 | P7 | `AREA 0` (default) | **finished in about 11 minutes**: 36.9 / 45.1 / 40.3 ns (`imem_data` to memory, to flop, flop to flop); l0 under `AREA 0`: 11.4 / 19.2 / 17.8 |

Segments of P4 to P6 (ns, slow corner, ideal wires, no I/O delays):

| segment | l0 (P6) | k0, divider stubbed (P5) | k0, single-cycle divider (P4) | k0, multi-cycle divider (P7) |
|---|---|---|---|---|
| `pc` to `imem_addr` | 0.9 | 1.2 | 1.1 | 1.2 |
| `imem_data` to `mem_addr`/controls/`mem_data_out` | 6.0 | 15.9 | 82.7 | 14.7 |
| `imem_data` to flop | 7.8 | 17.1 | 84.3 | 16.8 |
| `mem_data_in` to flop | 3.5 | 4.0 | 4.6 | 4.6 |
| `mem_error` to flop | 4.4 | 6.5 | 12.3 | 6.3 |
| `mem_ready` / `imem_ready` to flop | | 6.5 / 6.9 | 12.0 / 12.9 | 6.0 / 6.5 |
| flop to `mem_addr`/controls/`mem_data_out` | 4.9 | 14.9 | 82.2 | 14.1 |
| flop to flop | 7.7 | 17.8 | 83.7 | 17.5 |

## What was learned

1. **The default ABC script did not finish on k0 with a single-cycle divider (P1, P3); with the multi-cycle one it does (P8, about 11 minutes).** The ALU on its own, with the multiplier and divider in it, maps in 8 seconds with Yosys' plain `abc -liberty` (11,000 cells), and the shared
   structures (P3) did not help. LibreLane's default script (`AREA 0`: `fx`, `mfs`, `retime`, four `fraig_store`, `&dch`, `&nf`) does not finish on the whole core. The light script
   (`AREA 3`: `strash; dch; map; topo; buffer; upsize; dnsize`) does, in 1.5 minutes. It also sizes cells, so its ideal-wire numbers are about 2 times faster than `AREA 0`
   on l0 (P6 against 11.4 / 19.2 / 17.8 ns): the two scripts cannot be compared with each other. k0 numbers have to be compared with l0 numbers from the same script.
2. **The single-cycle divider is the critical path.** A shared unsigned restoring divider (32 chained subtract-and-compare stages) is single-cycle, preserves the spec and passes
   the 8 rv32um riscv-tests, and costs about 66 ns of the 83 ns. Everything else in k0 is about 2.3 times l0 (15.9 against 6.0 ns on the address path).
3. **What the rest of k0 adds to l0:** the multiplier (33x33, single-cycle), the atomics' read-modify-write result into `mem_data_out`, the pmp checks on the address and the stall
   network (`mem_ready`, `imem_ready` reach the flops in 6.5 to 6.9 ns).
4. The l0 changes in k0: trap split and address adder were already in, the register file reads the instruction fields (t20), `mem_fault` (t29) is not ported yet.

## Decision: the divider is multi-cycle (P7)

`core/divider.sv` does `div`, `divu`, `rem` and `remu` one bit per clock and holds the core with the same `stall` as a slow memory or the atomics' two phases. It is not a
pipeline: one instruction is in flight, the next starts when it has retired, instruction order is unchanged and traps stay precise. Results:

- A divide takes **34 clocks** (1 to load, 32 for the bits, 1 to retire) instead of 1; `mul`, `mulh`, `mulhsu` and `mulhu` stay at 1. The rv32um divide tests went from 143 to 440 cycles
  (9 divisions each). Against software division on a core without M (`__divsi3` in libgcc, a loop of a hundred or more instructions), 34 clocks is still cheaper.
- The core path dropped from 82.7 to 14.7 ns (`imem_data` to memory) in the ideal-wire preview, in line with the stubbed run (P5).
- An interrupt during a divide is taken at once; the divide is abandoned and runs again after `mret`. Worst-case interrupt latency grows by up to 34 clocks.
- Checks: riscv-tests 74/74, also with wait states (`FETCH_WAIT=2`, `DATA_WAIT=3`), `test_divider.sv` (the old ALU divide vectors, plus the clock count and two divides back to back),
  `programs/run.sh` PASS.

## Next

- Port `mem_fault` (l0 t29) to k0.
- A `k0.sdc` made from `l0.sdc` and a registered memory interface (`TIMING.md` of l0, section 8), then the first full `k0-try<N>`.
