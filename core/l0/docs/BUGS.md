# l0 bugs found and fixed

Sixteen defects were found while bringing l0 up against the official riscv-tests. All are
fixed. Each row gives what was seen, why it happened, what changed and the commit that holds
the fix (`git show <hash>`). Paths are relative to `core/l0/`.

Words: a **lane** is the byte or halfword inside a 32-bit word that an access addresses.
**Latch** means a combinational block that does not assign an output on every path, so
hardware keeps the old value. **Retire** means an instruction finishes and its effects
(register, memory, CSR) become visible.

## Summary

| group | bugs | commits |
|---|---|---|
| Memory | 1, 2, 7, 14 | `f6bb252`, `194d58a` |
| Program counter and traps | 3, 4, 5, 6, 8, 9 | `0c95273` |
| Control and CSR datapath | 10, 11, 15 | `0c95273`, `8d675e2` |
| Instruction decode and ALU | 12, 13 | `44d4719`, `2373206` |
| Tests | 16 | `bddfca5`, `f6bb252`, `44d4719`, `2373206`, `0c95273` |

## Memory (`src/memory.sv`)

| # | symptom | cause | fix | commit |
|---|---|---|---|---|
| 1 | `sb` and `sh` clobbered the whole word | the store wrote the full `data_in` word whatever the access width | write only the addressed byte or halfword lane | `f6bb252` |
| 2 | `lb lh lbu lhu` ignored the address offset and always returned the low byte | memory returned the whole word and `control` sign-extended its low bits | memory returns the addressed lane zero-extended, `signext` makes it signed | `f6bb252` |
| 7 | an out-of-bounds store still wrote | the write path wrapped the address and stored | a faulting access neither reads nor writes | `f6bb252` |
| 14 | wiring `rst_n` would have wiped the program | reset zeroed the array unconditionally; it only worked because `rst_n` was not connected | reset restores the preloaded image. Words past the end of a shorter image are zeroed first, because `$readmemh` leaves them unknown | `f6bb252`, `194d58a` |

## Program counter and traps (`src/control.sv`, `src/csrfile.sv`, `src/shared.sv`)

| # | symptom | cause | fix | commit |
|---|---|---|---|---|
| 3 | pc stuck, or a stale `jal` immediate ran; riscv-tests hung on the first instruction after reset | `next_pc` was written by blocking assignments in a combinational block and by non-blocking ones in the clocked block, plus a `manual_pc_set` flag | `pc` is the only register in `control`; `next_pc` is purely combinational and registered once per clock | `0c95273` |
| 4 | one extra instruction ran after every trap, and a trap took a cycle to redirect | `trap_target_pc` and `trap_handled` were registered in the CSR file, one cycle late | `csrfile` exposes a combinational `trap_vector`; the pc redirects in the same cycle | `0c95273` |
| 5 | `mcause` values were not the spec values (ecall 3 not 11, ebreak 4 not 3, illegal 5 not 2) | the enum was invented instead of taken from the privileged spec | `shared.sv` uses the spec codes 0 to 7 and 11. Load and store faults and misaligned accesses are told apart | `0c95273` |
| 6 | an out-of-bounds access was reported as misaligned | copy and paste in `control` | out-of-bounds raises load or store access fault (5 or 7) | `0c95273` |
| 8 | illegal instructions never trapped | the branch meant to catch them was unreachable and the decode defaults did nothing | an `illegal` flag covers unknown opcodes, reserved load/store/branch widths, bad `f7`, reserved `slli` shamt and unknown SYSTEM encodings. A trapping instruction does not retire | `0c95273` |
| 9 | `mret` did not restore `MIE` from `MPIE` | `csrfile` had no `mret` input | new `mret` input: `MIE = MPIE`, `MPIE = 1`, `MPP = M` | `0c95273` |

## Control and CSR datapath (`src/control.sv`)

| # | symptom | cause | fix | commit |
|---|---|---|---|---|
| 10 | CSR operations repeated every cycle | `csr_op` and other outputs had no default, so they latched | every combinational output gets a default at the top of its block | `0c95273` |
| 11 | `csrr`, `csrrw` and friends never wrote the old CSR value to `rd` | the decoder leaves `reg_write` low for SYSTEM and `control` did not compensate | `control` enables the register write for CSR instructions | `0c95273` |
| 15 | simulation hung once the core was otherwise fixed | defaults written to `alu_op` and `alu_a` and then overwritten fed `alu_result` back into the same block, which never settled. iverilog also rejected constant selects in `always_comb` | feedback signals are computed into locals and published once; trap selection is a second block. Both are plain `always @*` | `0c95273`, `8d675e2` |

## Instruction decode and ALU (`src/decoder.sv`, `src/alu.sv`)

| # | symptom | cause | fix | commit |
|---|---|---|---|---|
| 12 | `lui` and `auipc` lost bits 31:20 | the decoder ran the already shifted 32-bit value through the 20-bit sign extender | `lui` and `auipc` use the 32-bit pass-through | `44d4719` |
| 13 | `sll srl sra` with a register shift amount above 31 gave wrong results | the ALU shifted by all 32 bits of operand `b` | the ALU uses `b[4:0]` | `2373206` |

## Tests (`tests/`)

| # | symptom | cause | fix | commit |
|---|---|---|---|---|
| 16 | the tests could not fail | `test_failed` was never initialised, so an unknown value compared false and a run looked clean. `test_control` asserted nothing, `test_memory` used random out-of-bounds addresses and `test_decoder` did not compile (stale `alu_op` port) | every test initialises `test_failed`. `test_control` runs a program and checks registers, memory and pc. `test_memory` is rewritten with directed lane, misalignment, bounds and reset cases. `test_decoder` is rewritten around a `check` helper covering every instruction class. `test_alu` gains shift cases | `bddfca5`, `f6bb252`, `44d4719`, `2373206`, `0c95273` |

## Result after the fixes

riscv-tests: l0 passes 53 of 53 (rv32ui and the applicable rv32mi tests). The k0 core,
which inherited the same fixes, passes 74 of 74 including rv32um and rv32ua. See
`CHIP.md` for what is run and what is excluded.
