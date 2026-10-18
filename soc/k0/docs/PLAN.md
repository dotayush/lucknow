# Plan: Linux NOMMU on k0

Goal: a Linux kernel without an MMU boots on k0 to a shell prompt on the uart, in simulation
first, then on an FPGA if one is available. "Boots" means: kernel banner on the console,
timer ticks, a userspace `init` runs and prints, then a small shell takes typed input.

## Status

Done: Linux 6.12.112 (no MMU, M-mode kernel build) boots on k0 in the Verilator model to a busybox shell
on the uart and runs commands typed at it, from a script or from your terminal (`linux/shell.sh`). The same
image on QEMU gives the same output (`linux/qemu.sh`). `linux/test.sh` and `linux/test_busybox.sh` check it.
The how-to and the findings are in `LINUX.md`.

| phase | state | notes |
|---|---|---|
| 0 toolchain and reference | done | kernel 6.12.112 pinned in `linux/build.sh`. The bare-metal `riscv32-unknown-elf` gcc builds the kernel. QEMU 10.0 (unpacked from the Debian packages without root) boots the same image and prints the same command output, `linux/qemu.sh`. The kernel's own `dtc` builds the device tree. `bc` was missing and was built from source |
| 1 boot interface | done | rom sets `a0`, `a1`. `programs/` has no a0/a1 print test, the kernel finding its device tree is the check |
| 2 ram and simulator | done | 16 MiB ram (8 MiB is not enough for busybox), Verilator model (`sim/`), about 1.7 MIPS. No trace diff against another model yet (the `+trace` option exists) |
| 3 timer, interrupts, console | done | CLINT timer, PLIC and the 8250 driver work (as `ns16550a` with FIFOs now). The kernel probes and emulates misaligned accesses (one trap at boot). Overruns happen if a typed byte arrives before the previous one was read: the uart has no fifo |
| 4 user mode | done | the experiment (MPP stuck at `11`) gave `Oops - environment call from M-mode` at the first syscall of `init`, so user mode was needed. Implemented, see `CHIP.md` |
| 5 userland | done, except storage | busybox and uClibc-ng from Buildroot as flat binaries, several processes, pipes. The cpio is embedded in the kernel, there is no block device |
| 6 regression | done | `linux/test.sh`, `linux/test_busybox.sh`. Kernel and toolchain versions pinned in the scripts, docs updated. riscv-tests pass (also with wait states, `riscv/run.sh`) |

The rest of this file is the plan as it was written. Items marked **(verify)** were from memory of the kernel
sources before any of this was tried; the table above and the findings below record what turned out to be true.

Findings that changed the plan:
- The kernel is built for `rv32ima` without `C`. `zbb`, `zba`, `zicboz` are enabled by default and
  had to be turned off: the generated code contained `clz`, `cpop`, `rev8` behind runtime patching,
  which would only run on a core that reports them, but it is cleaner not to have them.
- NOMMU RISC-V user binaries are bFLT files loaded entirely in ram. A flat file is a 64 byte header plus
  position independent code, `linux/init/mkflat.py` writes it, no libc or elf2flt was needed for `init`.
- Linux needs `/dev/console` in the initramfs (`linux/initramfs.list`).
- `mstatus.MPP` and the user/machine distinction are used by `ret_from_exception` to know whether a trap came
  from a task. Without U-mode the first `ecall` from `init` fails.

Still open (not needed for the shell, listed in order of usefulness):
1. ~~busybox and a libc~~ done: Buildroot 2025.02.7, uClibc-ng, busybox as bFLT (elf2flt), `linux/buildroot/build.sh`, `linux/busybox.sh`, `linux/test_busybox.sh`. The shell runs pipes and several processes. Boot to the prompt is 92 million clocks, about a minute in Verilator. Needs 16 MiB of ram (8 MiB left no contiguous block for the 730 KiB busybox).
2. ~~A FIFO in the uart~~ done: 16 byte FIFOs, `ns16550a`, trigger levels, character timeout. Linux types a whole line with 2 bit times between bytes.
3. ~~A reference run on QEMU~~ done for command output (`linux/qemu.sh`). Instruction-by-instruction trace diff: `linux/tracediff.sh`, identical for the first 205,000 non-loop instructions, then a timing dependent difference in `printk` (`LINUX.md`).
4. ~~PMP~~ done in hardware (8 entries, `CHIP.md`). The kernel does not use it to isolate tasks.
5. Block device or a larger initramfs, FPGA bring-up (clock, memory controller, `timebase-frequency`).

## Why this is close

- NOMMU Linux needs no page tables or `satp`. Hardware needed: 32-bit RISC-V with `A`,
  a timer, an interrupt controller and a console.
- The kernel has an M-mode build (`CONFIG_RISCV_M_MODE`, only selectable without an MMU)
  that runs with no SBI firmware (OpenSBI) in front of it. It uses `mstatus`, `mie`, `mtvec`,
  `mret` directly. That fits a core that only has M-mode.
- k0's devices already copy the QEMU `virt` layout (ns16550 uart, SiFive CLINT, SiFive PLIC,
  ram at `0x8000_0000`), which the kernel has drivers for. QEMU `virt` is therefore a usable
  reference to bring up the same kernel and device tree before touching RTL.
- Atomics, 64-bit counters, `time` CSR and CLINT-based timer are done.

## Gaps, ranked by how likely they block boot

| # | gap | why it matters | phase |
|---|---|---|---|
| 1 | ram is 32 KiB | a tiny NOMMU kernel + initramfs needs 4–8 MiB | 2 |
| 2 | no U-mode: `mstatus.MPP` is stuck at `11` | the kernel tells "trap came from user" from "trap came from kernel" by the previous-privilege bit; with it stuck, user tasks are never rescheduled or signalled on return from a trap **(verify)**. Also no isolation between kernel and user | 4 |
| 3 | no hardware misaligned loads/stores | the kernel and some userland do unaligned accesses. They trap (cause 4/6). Either build with `-mstrict-align`, emulate in a handler, or fix in hardware **(verify)** | 3 |
| 4 | boot passes no `a0`/`a1` | kernel expects hart id in `a0` and device tree address in `a1`. The rom is two instructions | 1 |
| 5 | no way to load an image except `$readmemh` | fine for sim; large images are slow to preload as text | 2 |
| 6 | simulation speed (iverilog) | boot is tens of millions of instructions **(estimate)**. iverilog may take hours; Verilator minutes | 2 |
| 7 | no Zifencei/Zicntr behaviour questions | kernel build may demand `zifencei`: `fence.i` already works, so only the `-march` string matters | 0 |
| 8 | `wfi` is a no-op | idle loop just spins. Correct, only wasteful | none |
| 9 | stored-but-inert CSRs (`mcounteren`, PMP, `medeleg`) | harmless in M-mode kernel, would matter for S-mode | none |

Things that are **not** gaps: C extension (build kernel and userland without it, k0 already
requires 4-byte aligned fetch), FPU (config off), MMU, S-mode, SBI.

## Phase 0: toolchain and reference (no RTL)

1. Pick a kernel: latest LTS that still has `CONFIG_RISCV_M_MODE` and NOMMU RV32 support
   **(verify both)**. Pin the exact version and commit in this doc once chosen.
2. Build a toolchain that can produce Linux userland for `rv32ima` (ilp32): use Buildroot
   or crosstool-ng. The existing `$EDA/riscv32/bin/riscv32-unknown-elf-*` is bare-metal, fine
   for the kernel itself (`CROSS_COMPILE=`), not for userland.
3. Choose userland. NOMMU cannot `fork()`: needs `vfork`, and binaries in FLAT (bFLT) or
   FDPIC format, not plain ELF. Candidates: busybox with uClibc-ng + `elf2flt`
   (Buildroot supports this), or nommu busybox built static. RV32 NOMMU userland support in
   libc **(verify, this is the riskiest software item)**. Fallback for first milestones: a
   few-hundred-byte `init` written in assembly or freestanding C, no libc, packaged as flat.
4. Write the device tree (`k0.dts`): one hart `riscv,isa = "rv32ima_zicsr_zifencei"`,
   `mmu-type` absent, `timebase-frequency` = clock, memory node, `ns16450` uart at
   `0x1000_0000` with `interrupts = <10>`, `sifive,clint0` at `0x0200_0000`, `sifive,plic-1.0.0`
   at `0x0c00_0000` with `riscv,ndev = <31>` and `interrupts-extended` listing only the M-mode
   context (`<&cpu0_intc 11>`). Compile with `dtc` (not installed yet).
5. Boot the kernel + DT on QEMU `rv32 virt` (not installed yet) as the reference, with the
   same kernel config. Save its full boot log. This separates "kernel config is wrong" from
   "k0 is wrong" for every later step.

Exit: kernel `Image` and DTB that boot to a shell on QEMU; documented `.config`.

## Phase 1: boot interface and a kernel that says something

1. Boot rom: set `a0 = 0` (hart id), `a1 = DTB address`, then jump to the kernel entry.
   Today it only jumps to `0x8000_0000`. Decide where the DTB lives (end of ram, or placed by
   the preload). Check load offset in the kernel image header (`text_offset`) **(verify)**.
2. Add a test for it in `programs/` that checks `a0`/`a1` arrive (print them on the uart).
3. Build a kernel with `earlycon` only and no initramfs. On k0 success is the earlycon
   banner followed by the "no init found" panic. That already exercises: fetch from ram, the
   trap vector, `ns16450` earlycon writes, and the whole boot path up to `start_kernel`.

Exit: banner appears in simulation, even if it dies afterwards.

## Phase 2: ram size and a simulator that can finish

1. Raise `RAM_WORDS` to cover 8 MiB (2,097,152 words). The ram array and `$readmemh` are
   ok with that size in iverilog, but check memory use and elaboration time.
2. Add a Verilator build of `soc` with a C++ or SV harness: clock, reset, uart sink to
   stdout, optional uart source from a file, image preload from a binary (not hex text),
   cycle limit. The existing tests use iverilog-only idioms (`$readmemh` parameters,
   hierarchical references); the harness can be a new top without touching them.
3. Same boot-to-banner test as phase 1, but run from the Verilator build, and time it.
   Record clocks per instruction and wall time per million instructions here.
4. Add a trace option: print `pc` on every retire (or on traps) to a file, for diffing
   against QEMU's `-d in_asm` / `-d exec` output when something diverges.

Exit: kernel banner in Verilator, with wall-clock numbers recorded.

## Phase 3: kernel with timer, interrupts, scheduler

1. Enable the CLINT timer and PLIC drivers, `HZ` as low as the kernel allows (fewer ticks
   in simulation). Boot should pass `calibrate`/`clocksource` and the scheduler starts.
2. `console=ttyS0` with the 8250 driver: moves from earlycon to the interrupt-driven
   serial driver. The uart is a 16450 with one-byte buffers, so check the driver is in
   `ns16450` mode and does not poll `THRE` faster than the line sends.
   Expect to hit the receive overrun case: a byte arrives while the handler is still busy
   (no FIFO). Slow clocks per bit (`UART_CLKS_PER_BIT`) make this a non-issue in simulation.
3. Misaligned accesses: run until the first misaligned trap, or build with `-mstrict-align`
   and see whether any are left. If the kernel does not handle them in M-mode **(verify)**,
   either add a small emulator in the kernel's trap path or implement them in the data port
   (split into two bus transfers, which the existing stall mechanism already supports).
   Prefer hardware if there are more than a handful, since userland will be full of them.
4. Make `mcounteren` irrelevant (no U-mode yet), `minstret`/`time` are already readable.

Exit: kernel reaches `init` handoff with timer ticks and a working serial console.

## Phase 4: privilege levels (the main RTL work)

Run user code in U-mode, kernel in M-mode, as the M-mode kernel build does on boards that
have no S-mode. This is only needed if the experiment below shows it matters.

Experiment first: run the kernel + a trivial `init` with `MPP` stuck at `11`. If `init` runs
and the kernel keeps scheduling, note what breaks (signals, preemption, `ecall` cause 11 vs 8)
and decide. Expect it to be insufficient for a real shell **(verify)**.

If U-mode is needed:
1. Add a privilege register (`priv`: M or U) in `csrfile`/`control`. Reset to M.
2. `mstatus.MPP`: store 2 bits, legal values `00` and `11` (others round to the nearest
   supported one). Trap entry: `MPP = priv; priv = M`. `mret`: `priv = MPP; MPP = U` (the
   lowest supported). `MPRV`, `MXR`, `SUM` stay 0.
3. In U-mode: CSR instructions with address bits [9:8] != 0 (machine and supervisor CSRs)
   and `mret`/`wfi` trap as illegal instruction; the `cycle/time/instret` aliases honour
   `mcounteren` (reset to 0: traps in U-mode, kernel may enable them).
4. `ecall` from U-mode raises cause 8 (add to `trap_cause_e`; `mcause` is 4 bits wide which
   is enough).
5. No memory protection: without PMP, U-mode may touch anything. Acceptable for NOMMU (the
   kernel assumes tasks are friendly), but record it. Implementing PMP is optional, later.
   **(verify)** that the privileged spec's behaviour for "no PMP implemented" allows U-mode
   accesses, and that `pmpaddr*` as plain storage does not confuse the kernel's probing.
6. Tests: extend `test_csrfile` and `test_control` for the new `MPP` and privilege rules.
   Add a bare-metal program (`programs/umode.S`) that drops to U-mode, makes an `ecall`
   (cause 8), makes an illegal CSR access (cause 2), and returns. The riscv-tests `p`
   environment runs in M-mode only, so it neither covers nor breaks.

Exit: kernel can enter user mode, take a syscall, and return, with a timer interrupt
preempting a spinning user task.

## Phase 5: userland and a shell

1. initramfs embedded in the kernel image (`CONFIG_INITRAMFS_SOURCE`). No block device
   needed.
2. First a one-process `init` that prints and `reboot`s/`exit`s, then a busybox shell.
3. Typed input: reuse the `uartrx` mechanism (RX string from a file) in the Verilator
   harness, so "type `echo hi`, expect `hi`" is a regression test.
4. Record: boot time in simulated clocks, and memory use (`free`).

Exit: shell prompt, typed command runs and prints, in simulation.

## Phase 6: regression and cleanup

- A single script that builds the kernel + DT + rootfs, runs the Verilator sim, and
  compares the console log against an expected tail. Not part of every unit test run
  (too slow); a separate entry next to `riscv/run.sh` and `programs/run.sh`.
- Pin versions: kernel, toolchain, Buildroot, riscv-tests (already pinned by commit).
- Update `README.md` and `CHIP.md` with what changed (U-mode, ram size, boot ABI).

## Optional, after boot works

- Hardware: a pipelined core or a multi-cycle divider if frequency matters on FPGA (the
  single-cycle `/` and `%` are a long combinational path).
- Storage: an SD-card-over-SPI or virtio-mmio block device for a root filesystem.
- Debug: the debug trigger module so `breakpoint` runs; semihosting for faster console.
- Real board: pick an FPGA board, memory controller, clock; measure `timebase-frequency`.

## Risks, in order

1. Userland on RV32 NOMMU (libc, FLAT/FDPIC) may not be supported out of the box. Mitigation:
   the freestanding `init` fallback keeps every earlier milestone testable.
2. M-mode kernel build bit-rot. Mitigation: pin an LTS release known to boot on QEMU
   (phase 0), and keep the QEMU reference.
3. Simulation too slow to boot with iverilog. Mitigation: Verilator in phase 2; reduce
   `HZ`, kernel log level and initramfs size.
4. U-mode semantics subtly wrong (illegal-instruction rules, `MPP` edge cases).
   Mitigation: the rv32mi tests that exercise `mstatus`, and writing the U-mode program
   test before touching the kernel.
5. The core has had no run beyond hand-written programs and riscv-tests, so kernel
   boot may find new ISA bugs: use the trace diff against QEMU to find the first
   diverging instruction.
