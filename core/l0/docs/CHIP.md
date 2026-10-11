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

**CSRs**

The CSR file is a flat 4096-entry array, so *any* CSR address reads and writes like plain
storage, including ones with no behaviour (for example `mscratch`, `mcounteren`, `pmpaddr*`).
These have behaviour:

| CSR | address | notes |
|---|---|---|
| `mstatus` | 0x300 | trap hardware edits `MIE` (bit 3), `MPIE` (bit 7), `MPP` (bits 12:11). The rest is storage |
| `misa` | 0x301 | `0x40000100`: 32-bit, RV32I. Read only |
| `mie` / `mip` | 0x304 / 0x344 | plain storage, nothing drives or reads them |
| `mtvec` | 0x305 | handler base |
| `mepc` `mcause` `mtval` | 0x341 0x342 0x343 | written by traps |
| `mcycle` | 0xB00 | 32-bit, +1 per clock. No `mcycleh`, no `minstret` |
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
| `src/control.sv` | top. Datapath muxing, next pc, trap selection |
| `src/decoder.sv` | splits an instruction into fields and picks the immediate format |
| `src/alu.sv` | add, sub, xor/or/and, signed and unsigned compare, shifts. Flags `zero carry overflow` exist but nothing consumes them |
| `src/regfile.sv` | 32 registers, two read ports (combinational), one write port, `x0` never written |
| `src/signext.sv` | sign/zero extension for immediates and for sub-word load results |
| `src/csrfile.sv` | CSR array, trap/`mret` side effects, `mcycle` |
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

`control` is the whole core: `clk`, `rst_n` (asynchronous, active low) and the parameters
`DATA_WIDTH`, `WORDS`, `IMEM_INIT`, `DMEM_INIT`. The memories are inside it, there are no
external ports. Reset puts pc at 0, clears registers and CSRs and reloads both memories.

## Verification

- `tests/test_<module>.sv` for every module (print `Test passed!` / `Test failed!`), and
  `test_control.sv`, which runs a small program and checks the registers.
- `riscv/run.sh` builds and runs the official riscv-tests: every rv32ui test except `fence_i`
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
