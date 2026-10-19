# l0

A small 32-bit RISC-V core: RV32I plus Zicsr, machine mode only, one instruction per clock.
It is meant to be read, simulated and dropped into a design that needs a minimal central
control unit. It is not a system: it has no bus, no peripherals and no interrupts.

## Words used below

| word | meaning |
|---|---|
| RV32I | the base 32-bit RISC-V integer instruction set: 32 registers, add/logic/shift, loads, stores, branches, jumps |
| Zicsr | the extension that adds the `csrr*` instructions to read and write control and status registers |
| CSR | control and status register: a numbered (12-bit) register holding core state such as the trap vector |
| M-mode | machine mode, the highest privilege level. The only one l0 has, so every instruction runs in it |
| trap | the core stops the current instruction and jumps to a handler. Raised by exceptions (and, in other cores, interrupts) |
| single-cycle | fetch, decode, execute, memory access and write back all happen in one clock |
| Harvard | instructions and data live in two separate memories, each with its own address port |
| `mepc` / `mcause` / `mtval` / `mtvec` | CSRs the trap hardware uses: pc of the faulting instruction / why / extra detail (bad address or instruction) / where the handler is |
| `mret` | the instruction that returns from a trap handler to `mepc` |

## What it implements

**Instructions**
- all of RV32I: `lui auipc jal jalr`, six branches, five loads (`lb lh lw lbu lhu`),
  three stores (`sb sh sw`), the register and immediate ALU operations, shifts.
- `fence` as a no-op (one core, in order, nothing to order).
- Zicsr: `csrrw csrrs csrrc` and their immediate forms. A CSR is read only when it has to be
  (`csrrw` with `rd = x0` does not read; `csrrs/c` with `rs1 = x0` does not write).
- `ecall`, `ebreak`, `mret`. `wfi` is a no-op because nothing can wake the core.
- Not implemented: M (multiply/divide), A (atomics), C (compressed), F/D, `fence.i`.

**Traps** (follow the privileged spec; `mcause` is a 4 bit exception code)

| code | cause | `mtval` |
|---|---|---|
| 0 | instruction address misaligned (pc or a jump/branch/`mret` target not 4 byte aligned) | the target |
| 1 | instruction access fault (fetch outside memory) | pc |
| 2 | illegal instruction (unknown opcode, reserved funct bits, reserved load/store width, unknown `system` encoding) | the instruction |
| 3 | `ebreak` | 0 |
| 4 / 6 | load / store address misaligned | the address |
| 5 / 7 | load / store access fault (address outside memory) | the address |
| 11 | `ecall` from M-mode | 0 |

- Only one trap is taken per instruction, first match wins: fetch fault, `ecall`/`ebreak`,
  illegal, data fault, misaligned target.
- A trapping instruction does not retire: no register write, no memory write, no CSR write.
- On a trap: `mepc = pc`, `mcause`, `mtval` set; `mstatus.MPIE = MIE`, `MIE = 0`, `MPP = 11`;
  pc = `mtvec` (base only, mode bits ignored, no vectoring).
- `mret`: pc = `mepc`, `MIE = MPIE`, `MPIE = 1`.
- Misaligned data accesses are not handled in hardware, they trap (4 / 6).
- Inside `control.sv` the one trap that follows the branch compare (a taken branch to a target that isn't 4 byte aligned) is kept
  apart from the others (`trap_early`): the register file and the CSRs a trap does not touch use `trap_early` only, and the late
  decision reaches only `next_pc` and the trap record (`mepc`, `mcause`, `mtval`, `mstatus`). Behaviour is the same. It shortens
  the path from instruction to register (`librelane/TIMING.md`).

**CSRs**

Only the CSRs below exist, each as a named register in `csrfile.sv`. Any other address reads 0 and ignores writes,
without trapping.

| CSR | address | notes |
|---|---|---|
| `mstatus` | 0x300 | trap hardware edits `MIE` (bit 3), `MPIE` (bit 7), `MPP` (bits 12:11). The rest is storage |
| `misa` | 0x301 | `0x40000100`: 32-bit, RV32I. Read only |
| `mie` / `mip` | 0x304 / 0x344 | plain storage, nothing drives or reads them |
| `mtvec` | 0x305 | handler base |
| `mcounteren` | 0x306 | plain storage |
| `mscratch` | 0x340 | plain storage |
| `mepc` `mcause` `mtval` | 0x341 0x342 0x343 | written by traps |
| `pmpaddr0` | 0x3B0 | plain storage, no protection (the riscv-tests `pmpaddr` test reads it back) |
| `mcycle` | 0xB00 | 32-bit, +1 per clock, a write to it is overridden by the increment. No `mcycleh`, no `minstret` |
| `mvendorid` `marchid` `mimpid` `mhartid` | 0xF11..0xF14 | read only, all zero |

Writes to read-only CSRs are silently dropped (no illegal-instruction trap).

## Structure

```
                 +-----------+   instruction    +------------------+
   pc --------->| imem      |----------------->| decoder          |--> opcode, f3, f7, rs1, rs2, rd, imm
                 +-----------+                  +------------------+
                                                         |
 regfile (32 x 32, x0 = 0) <--> control ---- alu (add, logic, compare, shift)
                                   |  \--- signext (immediates, load results)
                                   |  \--- csrfile (CSRs, trap and mret updates)
                                   +------- dmem (data memory: addr, size, data)
```

`control.sv` is the only place with decisions: it selects ALU inputs, builds the next pc,
picks the trap and drives write enables. `pc` is the only state it holds itself.

| file | role |
|---|---|
| `src/shared.sv` | package `isa_shared`: opcodes, funct codes, ALU ops, CSR addresses, trap causes |
| `src/control.sv` | `l0_core`, the core. Datapath muxing, next pc, trap selection, no memory. Loads, stores and `jalr` compute `rs1 + imm` on their own adder, not through the alu; the register file reads the instruction fields, not the decoder's gated `rs1`/`rs2` |
| `src/l0.sv` | `control`: `l0_core` plus the two memories, the top the tests use |
| `src/decoder.sv` | splits an instruction into fields and picks the immediate format |
| `src/alu.sv` | add, sub, xor/or/and, signed and unsigned compare, shifts. Flags `zero carry overflow` exist but nothing consumes them |
| `src/regfile.sv` | 32 registers, two read ports (combinational), one write port, `x0` never written |
| `src/signext.sv` | sign/zero extension for immediates and for sub-word load results |
| `src/csrfile.sv` | the CSRs above, trap/`mret` side effects, `mcycle` |
| `src/memory.sv` | word array with byte/half/word access, alignment and bounds errors |

## Memory

- Two instances of `memory.sv`: instruction memory read at `pc`, data memory read and written
  by loads and stores. They are separate arrays, so a store cannot change code (no `fence.i`).
- Addresses start at 0 in both. Size is `WORDS` words (default 64; the riscv-tests runs use 8192 = 32 KiB).
  Anything at or above `WORDS * 4` is an access fault.
- Reads are combinational (data is there in the same cycle), writes land on the clock edge.
- Initial contents come from a `$readmemh` hex file (one 32-bit word per line):
  `IMEM_INIT` (default `./memory/test_rom.hex`) and `DMEM_INIT`.
- A faulting access neither reads nor writes.
- Sub-word loads return the addressed byte lane zero-extended, `signext` makes it signed when needed.

## Interface

`l0_core` (`src/control.sv`) is the core without memories, so it can be dropped into a design that owns the memory:

| ports | direction | meaning |
|---|---|---|
| `clk`, `rst_n` | in | clock, asynchronous active low reset. Reset puts pc at 0 and clears registers and CSRs |
| `imem_addr` | out | instruction address, always `pc` |
| `imem_data`, `imem_err` | in | the instruction word and its error code (`NO_MEM_ERROR`, `OUT_OF_BOUNDS`, `ADDRESS_MISALIGNED` from `isa_shared`) |
| `dmem_addr`, `dmem_wdata` | out | data address and store data |
| `dmem_size`, `dmem_read`, `dmem_write` | out | byte, half or word access, and which one. `dmem_write` is never set for a reserved store width |
| `dmem_rdata`, `dmem_err` | in | the addressed lane zero-extended, like `memory.sv`, and the error code |

The memory has to answer in the same cycle (combinational read); a write lands on the clock edge.

`control` (`src/l0.sv`) is `l0_core` plus the two memories of `memory.sv`, with the parameters `DATA_WIDTH`, `WORDS`,
`IMEM_INIT`, `DMEM_INIT` and only `clk` and `rst_n` as ports. The tests and the simulation use it. It also reloads both
memories on reset.

## Verification

- `tests/test_<module>.sv` for every module (print `Test passed!` / `Test failed!`), and
  `test_control.sv`, which runs a small program and checks the registers.
  From `core/l0` (`source eda.sh` provides iverilog): `iverilog -g2012 -o tests/results/test_alu.out src/shared.sv src/alu.sv tests/test_alu.sv && vvp tests/results/test_alu.out`;
  the top level test is `iverilog -g2012 -o tests/results/test_control.out -c compile.f && vvp tests/results/test_control.out`
  (`compile.f` keeps the compile order; `vvp` also writes a `.vcd` for gtkwave).
- `riscv/run.sh` builds and runs the official [riscv-tests](https://github.com/riscv-software-src/riscv-tests) (cloned on first use
  into `core/l0/riscv-tests`, ignored by git; needs `riscv32-unknown-elf-gcc`, `source eda.sh` puts it on `PATH`, `TOOLCHAIN` is the
  prefix the script uses). `./riscv/run.sh` runs everything, `./riscv/run.sh addi lw` some tests: every rv32ui test except `fence_i`
  and `ma_data`, and the rv32mi tests `csr mcsr scall sbreak shamt ma_addr ma_fetch
  lh/lw/sh/sw-misaligned zicntr pmpaddr`. Pass is a `1` written to `tohost`.
- Not run, because the feature is absent: `breakpoint` (debug triggers), `illegal`
  (interrupts, vectored `mtvec`), `instret_overflow` (`minstret`).

The sixteen defects found while bringing the core up, with causes and fixes, are in `BUGS.md`.

## Limits worth knowing

- One clock per instruction means a long combinational path (fetch to write back). Fine in
  simulation, it sets the clock ceiling on a real chip.
- No stall mechanism: memories must answer in the same cycle.
- No interrupts of any kind, no counters besides 32-bit `mcycle`.
- No privilege modes below M, no memory protection, no virtual memory.
- Built for iverilog/yosys; `control.sv` uses `always @*` blocks on purpose because
  iverilog does not settle some `always_comb` loops there.
