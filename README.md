![img](./assets/logo.svg)

### lucknow.
"lucknow." is an open-source project where i'll publish a collection of
digital designs i've created at the heart of the city of lucknow, india!

### packages.
- ./core/l0
  - 32-bit, single-cycle, compute core
  - rv32i + zicsr
  - all code executes in machine mode (m-mode)
  - harvard memory architecture
  - traps follow the privileged spec (ecall, ebreak, illegal instruction, misaligned/out of bounds access)
  - no interrupts, no minstret
  - passes the official riscv-tests rv32ui suite and the rv32mi tests that apply to it (see [`core/l0/docs/CHIP.md`](./core/l0/docs/CHIP.md))
  - can be used as a design block in systems where a minimal ccu
  (central control unit) is required
  - educational/hobby purpose

- ./soc/k0 (work in progress)
  - core l0 plus the m extension (mul, mulh, mulhsu, mulhu in one clock; div, divu, rem, remu in 34 clocks, one bit per clock)
    and the a extension (lr.w, sc.w, and the nine word amos; one word reservation, any store clears it)
  - one memory map for both ports (qemu virt like): boot rom @ `0x0000_1000` (reset vector),
    ram @ `0x8000_0000`. the instruction port and the data port see the same ram, so code can
    be stored and run (`fence.i` works)
  - `valid/ready` style handshakes on both ports: the core stalls while a fetch or access is
    not ready, `bus.sv` can add wait states (`FETCH_WAIT`, `DATA_WAIT`) to model slow memory
  - uart @ `0x1000_0000`: 16550 register layout (what the 8250 driver and earlycon use), byte accesses, 8N1 at
    clk/`UART_CLKS_PER_BIT` (>= 4); `UART_ECHO=1` prints the bytes in simulation. transmit and receive, 16 byte
    fifos in each direction when `FCR` bit 0 is set (a 16550A: use `ns16550a` in a device tree, trigger levels and a
    character timeout interrupt), otherwise one byte each way (a 16450), overrun and framing error in `LSR`,
    received data / transmitter empty / line status interrupts (`IER`, `IIR`), divisor latches (`DLAB`) are stored
    only. with the fifos off a program has to drain the receiver within one byte time
  - clint @ `0x0200_0000` (qemu virt / sifive layout, one hart): `msip` @ `+0x0`, `mtimecmp` @ `+0x4000`,
    `mtime` @ `+0xBFF8`, word accesses; `mtime` counts clocks
  - plic @ `0x0C00_0000` (sifive / qemu virt layout): 31 level sources (uart is source 10, like qemu virt), 3 bit
    priorities, one context (machine mode of the hart), claim / complete, threshold; word accesses
  - machine interrupts: timer (mip.MTIP) and software (mip.MSIP) from the clint, external (mip.MEIP) from the plic,
    `mie`, `mstatus.MIE/MPIE`, taken
    between instructions (an interrupted instruction does nothing and is replayed after `mret`, `mepc` is its pc),
    `mtvec` direct and vectored mode; `wfi` is a no-op
  - counters: `mcycle`/`minstret` (64 bit, `mcycleh`/`minstreth`), `cycle`/`instret` aliases, `time`/`timeh` read
    from the clint's `mtime`
  - machine and user mode: `mstatus.MPP` (00 or 11), `mret` enters the mode in `MPP`, ecall from user is cause 8,
    machine csrs, `mret`, `wfi` and counters not in `mcounteren` are illegal in user mode, writing a read only csr
    is illegal; no pmp. `mstatus` has MIE, MPIE and MPP only, `mip` is read only
  - boot rom: `a0` = 0, `a1` = device tree at `0x807F_0000`, jumps to ram
  - runs a no-mmu Linux 6.12 to a shell, see [`soc/k0/docs/LINUX.md`](./soc/k0/docs/LINUX.md)
  - `soc.sv` wires the core to the bus; unmapped accesses, stores to the rom, non-byte uart accesses and
    non-word clint or plic accesses are access faults
  - passes riscv-tests rv32ui (including `fence_i`), rv32mi (including `illegal` and `instret_overflow`),
    rv32um and rv32ua, also with wait states
  - not done yet: more peripherals, s-mode (and a second plic context) and an mmu

### tools.
the open silicon tools (simulation, sky130 analog and digital flows) live in one directory outside the repository.
`.env` says where; `eda.sh` is the only script that sets them up.

```bash
cp .env.example .env     # once: set EDA to the tools directory
./eda.sh                 # menu: install, verify, shell, view, demo
source eda.sh            # put the tools on PATH in the current shell
```

what is installed and where: [`TOOLS.md`](./TOOLS.md). the flows (analog, digital, mixed signal) and what was verified:
[`FLOWS.md`](./FLOWS.md). the l0 place and route runs: [`core/l0/librelane/RUNS.md`](./core/l0/librelane/RUNS.md).

### license.

       ╱|、
     (˚ˎ 。7
      |、˜〵
     じしˍ,)ノ

the repository and everything within is licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.en.html).
Refer to [COPYING.md](./COPYING.md) for the full license text.
