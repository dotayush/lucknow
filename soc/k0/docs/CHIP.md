# k0

A small RISC-V system on a chip (SoC): the l0 core grown into RV32IMA, a memory bus with a
boot rom, ram and three peripherals (uart, clint, plic), and machine interrupts. Still
single-hart, machine mode only, work in progress. The platform deliberately mimics QEMU's
`virt` machine, so software written for that board finds the same devices at the same
addresses.

## Words used below

| word | meaning |
|---|---|
| RV32IMA + Zicsr | base integer set, **M** multiply/divide, **A** atomics, and CSR instructions |
| hart | a hardware thread: one core's instruction stream. k0 has one (`mhartid = 0`) |
| M-mode | machine mode, the highest privilege level, and the only one k0 has |
| CSR | control and status register, a numbered core register such as `mtvec` |
| trap | the core abandons the current instruction and jumps to a handler. An *exception* is caused by the instruction, an *interrupt* by something outside |
| `mepc` / `mcause` / `mtval` / `mtvec` | where to resume / why / extra detail (bad address or instruction) / where the handler is. `mcause` bit 31 set means interrupt |
| `mie` / `mip` / `mstatus.MIE` | interrupt-enable bits per source / interrupt-pending bits per source / global interrupt enable |
| `mret` | return from a trap handler |
| CLINT | core-local interruptor: a timer and a software-interrupt flag, per hart |
| PLIC | platform-level interrupt controller: collects device interrupt lines, ranks them, hands one to the hart |
| UART | serial port. The register layout is that of the 16550 chip that Linux's 8250 driver expects |
| AMO | atomic memory operation: read, modify, write memory as one indivisible step |
| LR / SC | load-reserved / store-conditional: an optimistic atomic pair, SC fails if something else wrote the word in between |
| MMIO | memory-mapped I/O: device registers accessed with ordinary loads and stores |
| wait state | extra clocks a memory takes to answer; the core freezes meanwhile |
| earlycon | Linux's minimal console driver used before the real serial driver loads |

## At a glance

- RV32IMA + Zicsr, M-mode only, no C (compressed), no F/D, no Zifencei-specific hardware (`fence.i` works because code and data share ram).
- Single-issue, in order, non-pipelined: one instruction at a time, **one clock per instruction** when memory answers immediately. Loads and stores that hit slow memory, and AMOs (two transfers), take more.
- Fully synchronous apart from async active-low reset (`rst_n`).
- Reset vector `0x0000_1000` (the boot rom).

## Memory map

| range | size | what | access |
|---|---|---|---|
| `0x0000_1000` | 4 KiB (`ROM_WORDS`=1024) | boot rom, preloaded from `memory/bootrom.hex` | read only; fetch and load |
| `0x0200_0000` | 64 KiB | CLINT | word, data port only |
| `0x0C00_0000` | 64 MiB window | PLIC | word, data port only |
| `0x1000_0000` | 256 B | UART (8 registers, repeated) | byte, data port only |
| `0x8000_0000` | `RAM_WORDS` words, default 8192 = 32 KiB | ram | byte/half/word, fetch and data |

Everything else is an access fault. So is: a store to the rom, a non-byte access to the
uart, a non-word or misaligned access to the clint or plic, and fetch from anywhere
but rom or ram. The boot rom holds two instructions that jump to `0x8000_0000`; the program
image is preloaded into ram with `RAM_INIT` (a `$readmemh` hex file, one word per line).
This is how every test and program starts: there is no loader or flash yet.

The instruction port and the data port see the *same* ram array, so a store is visible to
the next fetch. `memory/bootrom.hex` is only 2 words; the rest of the rom reads 0.

## Instructions

- **RV32I** as in l0 (see `core/l0/docs/CHIP.md`), plus:
- **M**: `mul mulh mulhsu mulhu div divu rem remu`, each computed combinationally in the
  ALU in one clock (division by zero and overflow follow the spec).
- **A**: `lr.w`, `sc.w` and `amoswap/add/xor/and/or/min/max/minu/maxu.w`.
  - Word only (`f3 = 010`); `.aq/.rl` bits are accepted and ignored (nothing reorders).
  - `lr.w` takes a one-word reservation. It is cleared by any store, any `sc`/AMO, a trap and `mret`.
  - `sc.w` succeeds (writes 0 to rd) only if the reservation is on the same address, otherwise writes 1 and stores nothing.
  - An AMO is two bus transfers (read, then write) of one instruction. An interrupt cannot land between them: the whole AMO is restarted after `mret`.
  - Misaligned `sc`/AMO traps even when `sc` would have failed.
  - Reported as a *load* fault for `lr`, a *store* fault for `sc` and the AMOs.
- `wfi` is a no-op (the core keeps running, software loops around it).
- `fence` is a no-op; `fence.i` is a no-op that is correct because fetch always sees the latest store.

## Traps

Exceptions use the same codes as l0 (0..7 and 11, see the l0 doc). The extra ones are the
**interrupts**, taken *between* instructions: the interrupted instruction does nothing at all
(no write, no memory transfer, `mepc` is its own pc) and is run again after `mret`.

| `mcause` | interrupt | source |
|---|---|---|
| `0x8000_000B` | machine external | PLIC (`mip.MEIP`, bit 11) |
| `0x8000_0003` | machine software | CLINT `msip` (`mip.MSIP`, bit 3) |
| `0x8000_0007` | machine timer | CLINT `mtime >= mtimecmp` (`mip.MTIP`, bit 7) |

- Priority when several are pending and enabled: external, then software, then timer.
  Exceptions are never masked.
- An interrupt is taken when `mstatus.MIE` is set and `mie & mip` is non-zero.
- Handler address: `mtvec` bit 0 = 0 *direct* (everything to the base), 1 *vectored*
  (interrupts to `base + 4 * code`, exceptions still to the base).
- Trap entry: `mstatus.MPIE = MIE`, `MIE = 0`, `MPP = 11`; `mret` reverses it.
- A trapping or stalled instruction does not retire.

## CSRs

As in l0, the file is a flat 4096-entry array, so unimplemented CSRs (`mscratch`,
`mcounteren`, `medeleg`, `pmpaddr*`, ...) read and write as plain storage rather than
trapping. Where behaviour exists:

| CSR | address | notes |
|---|---|---|
| `mstatus` | 0x300 | only `MIE` (3) and `MPIE` (7) are writable. `MPP` always reads `11`. Everything else reads 0 |
| `misa` | 0x301 | `0x4000_1101`: RV32, I, M, A. Read only |
| `mie` | 0x304 | writable bits 3, 7, 11 only |
| `mtvec` | 0x305 | bit 1 forced to 0; mode = bit 0 |
| `mepc` `mcause` `mtval` | 0x341..0x343 | written on traps |
| `mip` | 0x344 | read only: it *is* the three input wires |
| `mcycle(h)` | 0xB00 / 0xB80 | 64-bit, +1 per clock (includes stall clocks). Writable |
| `minstret(h)` | 0xB02 / 0xB82 | 64-bit, +1 per retired instruction. Writable |
| `cycle(h)` `instret(h)` | 0xC00.. | read-only aliases |
| `time(h)` | 0xC01 / 0xC81 | read from the CLINT's `mtime` |
| `mvendorid` `marchid` `mimpid` `mhartid` | 0xF11..0xF14 | zero, read only |

A write to either half of a 64-bit counter replaces the whole counter.
Writes to read-only CSRs are dropped without trapping.

## Devices

### UART (`0x1000_0000`)
16450-class: 16550 register layout without FIFOs, so one byte each way. Use
`compatible = "ns16450"` in a device tree. Byte accesses only. Fixed 8N1 at
`clk / UART_CLKS_PER_BIT` (default 8, minimum 4); the divisor latches (`DLAB`) are stored but
do not change the baud rate.

| offset | read | write |
|---|---|---|
| 0 | `RBR` received byte (clears DR) | `THR` send a byte; dropped if still sending |
| 1 | `IER` | `IER`: bit 0 rx data, 1 THR empty, 2 line status |
| 2 | `IIR`: 0x01 none, 0x06 line status, 0x04 rx data, 0x02 THR empty (reading clears 0x02) | `FCR` ignored |
| 3, 4, 7 | `LCR`, `MCR`, `SCR` stored only | |
| 5 | `LSR`: bit 0 DR, 1 overrun, 3 framing, 5 THRE, 6 TEMT (OE, FE clear on read) | |
| 6 | `MSR` = 0 | |

An overrun keeps the unread byte and drops the new one. Software has to drain the receiver
within one byte time. `ECHO=1` prints transmitted bytes in simulation. Interrupt is PLIC source 10.

### CLINT (`0x0200_0000`, sifive/qemu layout, one hart)
| offset | register |
|---|---|
| `0x0000` | `msip`: bit 0 is the software interrupt |
| `0x4000` / `0x4004` | `mtimecmp` low / high (resets to all ones: no timer interrupt until set) |
| `0xBFF8` / `0xBFFC` | `mtime` low / high, a 64-bit counter of clocks since reset (writable) |

Timer interrupt is level: high while `mtime >= mtimecmp`. Clear it by moving `mtimecmp` forward.

### PLIC (`0x0C00_0000`, sifive/qemu layout, one context = this hart's M-mode)
| offset | register |
|---|---|
| `0x000000 + 4n` | priority of source n (3 bits, 0 = never interrupts), n = 1..31 |
| `0x001000` | pending bits (read only) |
| `0x002000` | enable bits |
| `0x200000` | threshold: only priorities strictly above it interrupt |
| `0x200004` | read = claim (id of the best pending source, 0 if none), write = complete (write the id back) |

Sources are level-triggered. A claimed source stays blocked until completed, so a device that
is still asserting does not re-interrupt before the handler is done. Highest priority wins,
lowest id on a tie. Only the UART is connected (source 10).

## Bus and timing

`bus.sv` decodes addresses and also owns the timing model.

- Fetch port and data port are independent request/ready channels. The core presents an
  address and waits for `ready`; the transfer completes on the clock edge where both are high.
- `FETCH_WAIT` and `DATA_WAIT` add that many clocks to every *new* request, to test the core
  against slow memory. While waiting the whole core freezes: pc, registers, CSRs and memory
  are untouched, so an instruction happens exactly once.
- Device registers with side effects (UART `RBR/LSR/IIR`, PLIC claim) act only on the clock
  where the access completes, never on waiting clocks.
- Ram and rom reads are combinational; ram writes land on the completing edge.

## Files

| file | role |
|---|---|
| `core/control.sv` | the core: datapath, A-extension sequencing, interrupts, stalls, trap selection |
| `core/decoder.sv` `alu.sv` `regfile.sv` `signext.sv` | as in l0; the ALU also does M |
| `core/csrfile.sv` | CSRs, interrupt pending/enable logic, 64-bit counters |
| `core/cache.sv` | despite the name, a plain ram/rom array with a second read-only fetch port |
| `core/clint.sv` `plic.sv` `uart.sv` | the devices |
| `bus.sv` | address decode, wait states, device wiring |
| `core/soc.sv` | core + bus: ports `clk`, `rst_n`, `uart_rx`, `uart_tx` |
| `core/shared.sv` | package `isa_shared`: opcodes, ALU ops, CSR addresses, trap codes |
| `compile.f` | file list for iverilog |

## Verification

- `tests/test_<module>.sv` per unit (alu, bus, clint, control, csrfile, decoder, memory,
  plic, regfile, signext, uart) plus `test_amo_faults.sv`.
- `riscv/run.sh`: official riscv-tests rv32ui (including `fence_i`), rv32mi (including
  `illegal`, `instret_overflow`), rv32um and rv32ua. Works with wait states
  (`RV_IFLAGS="-Ptest_riscv.FETCH_WAIT=2 -Ptest_riscv.DATA_WAIT=3"`, see README).
- `programs/run.sh <name>`: bare-metal assembly programs run through the uart, output compared with `<name>.expect`:
  `hello`, `timer` (CLINT interrupts, direct and vectored), `irqatomic` (AMOs hit by
  interrupts are neither lost nor repeated), `uartrx` (typed bytes arrive by PLIC interrupt).
- Not run: `breakpoint` (debug triggers) and `ma_data` (hardware misaligned access).

## Not implemented

- S-mode and U-mode (`MPP` is stuck at `11`), `medeleg`/`mideleg`, `sret`.
- MMU, `satp`, page tables, `sfence.vma`; PMP (`pmpaddr*` is plain storage, no checks).
- C (compressed) and F/D; hardware misaligned loads/stores (they trap).
- Debug module and triggers, `mcounteren`/`mcountinhibit` behaviour, `mconfigptr`.
- More than one hart, more than one PLIC context, FIFOs in the UART.
- Any storage device, timer other than CLINT, interrupt sources other than the UART.
- Ram is small by default (32 KiB). Raise `RAM_WORDS` for anything larger.
