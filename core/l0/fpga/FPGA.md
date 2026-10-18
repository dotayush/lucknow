# l0_core on an FPGA (Lattice ECP5, open flow)

What l0 costs on the FPGA k0 is headed for, and which findings from the ASIC flow also show up here.
`./run.sh <new_dir> [25k|45k|85k]` reproduces it (yosys + slang front end, then nextpnr-ecp5, speed grade 6, no pin
constraints). k0 is larger than l0, so these counts are a lower bound for it, not an estimate.

## Result for `l0_core` (current RTL, 11 CSRs, memories outside)

| | ECP5-25F | ECP5-45F |
|---|---|---|
| LUT4 | 6351 | same |
| PFUMX + L6MUX21 (LUT-input muxes) | 2117 + 996 | same |
| carry cells (CCU2C) | 79 | same |
| flip-flops | 1408 | same |
| block RAM, distributed RAM | 0, 0 | same |
| slices used (TRELLIS_COMB) | 6533 of 24,288 (26%) | |
| I/O used | 170 of 197 (86%) | |
| clock to clock, fmax | 39.0 MHz | 41.2 MHz |
| `imem_data`/`dmem_*` input to flop | 35.6 ns | 35.1 ns |
| flop to output | 19.1 ns | 21.6 ns |
| input to output | 28.7 ns | 32.4 ns |

Input and output times include the I/O buffers. One seed; nextpnr results move a few percent with the seed.

## What it shows

1. **The register file becomes 1024 flip-flops plus read muxes, not RAM.** Yosys prints `Replacing memory \regs with list of
   registers`: the array has an asynchronous reset that clears all 32 entries, so it cannot map to the FPGA's distributed
   RAM. 0 RAM blocks are used. The ASIC flow showed the same structure (1024 flops, 7.7 ns of read mux).
2. **The longest path is the same one as in the ASIC flow**: instruction input, decode, register read, ALU (a ripple
   carry chain, `CCU2C`), then the branch, trap and CSR logic, to a flop. 35.6 ns here vs 31.6 to 35.8 ns in the slow corner of sky130.
   More than half of the FPGA path is routing: the first hop from `imem_data[21]` takes 6.7 ns and a later decode net 5.1 ns,
   while a LUT costs 0.24 ns. That points at fan-out as the common cause, in both flows (a decode or register-select
   signal reaches 1000 or more flops).
3. **Front end matters.** Yosys' built-in SystemVerilog reader printed `Package isa_shared not found for import, removing
   import statement` and produced 7828 LUT4 (wrong, about 20% too many). With the slang front end there are no warnings and 6351 LUT4.
   Any future yosys check of `core/l0` or `soc/k0` must use `plugin -i slang` and `read_slang`.

## Ideas this gives k0 (not tried)

- A register file without the array reset (or reset by initial value) would let the FPGA tool use distributed RAM,
  which removes most of the 1024 flops and the 32:1 muxes. It changes the documented "reset clears registers"
  behavior, so it needs a decision and the riscv-tests as the check. The ASIC flow would still use flops.
- The fan-out of the decode and register-select signals is the shared deficiency to look at first; both flows say so.
