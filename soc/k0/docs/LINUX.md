# Linux on k0

What runs, how to build it, how to use it, and what was learned. The chip itself is described in
`CHIP.md`, the plan this followed (with its findings) in `PLAN.md`.

## What works

A Linux 6.12.112 kernel without an MMU boots on k0 in a Verilator model and gives a busybox shell on the
uart. You can type at it from your terminal. Pipes, `$(( ))`, `/proc` and several processes at once work.
The same kernel image boots unchanged on QEMU's `virt` machine and prints the same command output, so
QEMU is the reference.

Not done: a real FPGA or chip (no clock, memory controller or board files), any block device (the root
filesystem is an archive inside the kernel image). PMP exists in hardware but Linux does not use it to
separate user tasks from the kernel (see Known gaps).

## Words

| word | meaning |
|---|---|
| NOMMU | Linux without a memory management unit: no virtual memory, every task shares one address space |
| bFLT | "binary flat": the executable format NOMMU Linux uses. A small header and position independent code, loaded whole into ram |
| elf2flt | the tool that turns a linked ELF into a bFLT file |
| initramfs | a root filesystem archive (cpio) compiled into the kernel and unpacked into ram at boot |
| uClibc-ng | a small C library for embedded Linux, supports NOMMU |
| busybox | one executable that is `sh`, `ls`, `cat` and about 300 other small tools |
| Buildroot | a build system that compiles a toolchain, a C library and busybox into one root filesystem |
| virt | QEMU's generic RISC-V machine. k0's memory map copies it |
| DTB | device tree blob: the description of the hardware the kernel receives in `a1` |

## Layout

| path | role |
|---|---|
| `core/` | the cpu and devices (see `CHIP.md`) |
| `memory/bootrom.hex` | boot rom: `a1` = `0x807F_0000` (DTB), `a0` = 0, jump to `0x8000_0000` |
| `sim/` | Verilator model of the soc. `build.sh`, `sim_main.cpp` |
| `linux/k0.dts` | device tree: 16 MiB ram, CLINT, PLIC, `ns16550a` uart, 1 MHz `timebase-frequency` |
| `linux/k0_defconfig` | kernel configuration (M-mode, NOMMU, rv32ima without C, `BINFMT_FLAT`, PLIC, CLINT) |
| `linux/init/` | a freestanding bFLT `init` with a tiny shell, no libc (the small image) |
| `linux/buildroot/` | Buildroot configuration for the busybox image |
| `linux/build.sh` | builds the kernel with the small init: `out/Image`, `out/k0.dtb` |
| `linux/busybox.sh` | rebuilds the kernel with Buildroot's cpio: `out/Image.busybox` |
| `linux/run.sh`, `shell.sh`, `qemu.sh` | boot on the model with scripted input, on the model with your terminal, on QEMU |
| `linux/test.sh`, `test_busybox.sh` | boot, type commands, check the answers |

Generated files live in `linux/out/` (ignored by git). Downloads and build trees live in
`~/personal/k0-linux` (`WORK=` changes that).

## Build

Host needs: a `riscv32-unknown-elf` gcc (the bare-metal one is enough for the kernel; set `TOOLCHAIN=`),
verilator, `bc`, `flex`, `bison`, `make`, `python3`, `curl`. Buildroot also wants `rsync`, `cpio`, `wget`.
Without root, build what is missing (`bc`, `rsync`) from source into `~/personal/k0-linux/tools/bin`: `linux/env.sh`
puts that directory on `PATH` after the system ones and each script checks its tools before it starts, so a
missing one is reported up front. `BC_PATH=<dir>` puts another directory first.

```
./sim/build.sh                       # sim/obj/Vsoc, 16 MiB ram, uart 256 clocks per bit
./linux/build.sh                     # downloads linux 6.12.112 once; Image, k0.dtb, init.flat
./linux/buildroot/build.sh           # 20 to 40 minutes: toolchain, uClibc-ng, busybox -> out/rootfs.cpio
./linux/busybox.sh                   # kernel with that cpio -> out/Image.busybox
```

## Use

```
./linux/shell.sh                     # busybox on your terminal, boots in about a minute, Ctrl-] quits
IMAGE=Image ./linux/shell.sh         # the small init and its shell instead
./linux/test.sh                      # small image: types commands, checks answers (about 2 min)
./linux/test_busybox.sh              # busybox image, same idea
```

`sim/obj/Vsoc` options: `+image=file[@hexaddr]` (repeatable), `+rx=file`, `+rx_delay`, `+rx_gap`,
`+interactive`, `+max_cycles`, `+stop_on=a|b`, `+trace=file` (pc of every retired instruction).

### Run on QEMU (fast, and the reference)

```
./linux/qemu-fetch.sh          # once, only if qemu-system-riscv32 is not installed and you have no root
./linux/qemu.sh                # busybox in this terminal. Ctrl-a x quits
WINDOW=1 ./linux/qemu.sh       # the console in a GTK window
IMAGE=Image ./linux/qemu.sh    # the small shell instead
```

It boots in a second or two, against about a minute and a half on the model, and runs the same kernel image
(k0 copies QEMU's `virt` memory map). `qemu.sh` takes the emulator from `PATH`, else from `$WORK/qemu-deb`
where `qemu-fetch.sh` unpacks the Debian packages. `QEMU=`, `QEMU_DATA=` and `QEMU_MODULES=` override it.

QEMU makes its own device tree, so the boot log differs from the model's (timestamps, `base_baud`, the PLIC
size); the commands' output is the same. Typed input from a pipe needs a pause so it arrives after the
prompt: `(sleep 8; echo uname -m; sleep 3) | ./linux/qemu.sh`. `hpmstat` says the counters are not readable
there: QEMU resets `mcounteren` to 0 and has no event counters beyond the three standard ones.

`WINDOW=1` needs the `ui-gtk.so` module (Debian `qemu-system-gui`, which `qemu-fetch.sh` also unpacks) and a
`$DISPLAY`. The kernel has no framebuffer driver, so the window is the same serial text console the model's
uart carries, not graphics.

### Performance counters from the shell

`hpmstat` (in the busybox image, `linux/buildroot/src/hpmstat.c`) reads the core's counters from user
mode. Alone it prints the totals since reset; with a command it prints what that command cost:

```
~ # hpmstat ls /
cycles               2064495
instructions         2062781
loads                511208
stores               618495
branches taken       111672
...
cycles/instruction   1.00
```

The counts are the core's, not the process's: the kernel's work for the command (`vfork`, loading the flat
binary, the console driver) and any other process that ran in between are in the numbers. Cycles per
instruction is 1.00 on the model because its ram answers at once; wait states on the bus show up as
`fetch wait clocks` and as cycles above instructions. Linux's own `perf` is not available: it needs the
SBI PMU extension or a supervisor-mode kernel, and this kernel runs in machine mode without firmware.
Two details worth knowing when adding your own tools: NOMMU binaries need `-fPIC -Wl,-elf2flt="-r -s<stack>"`
(without `-r` the relocations are dropped and the program faults on its first data access).

## Trace diff against QEMU

`linux/tracediff.sh` runs the first N instructions on the model and on QEMU (same kernel, same device
tree) and compares the program counter of every instruction. `N=4000000 ./linux/tracediff.sh`.

- QEMU logs one line per instruction (`-accel tcg,one-insn-per-tb=on -d exec`). It leaves out the
  instruction after a store to a device, so one missing instruction is not counted as a difference.
- Wait loops run a different number of times because the model's uart is 256 clocks per bit and QEMU's is
  instant, so every iteration of a short loop is dropped on both sides before comparing.
- Result: the same instructions, in the same order, for the first 205,000 non-loop instructions (a million
  and more with the loops), through the early kernel and `printk`. The first difference is inside
  `printk`'s console handover (`console_lock_spinning_enable` against `..._disable_and_check`): which one
  runs most likely depends on whether a timer interrupt arrived during a console write, which depends on time (not checked instruction by instruction).
  Interrupts are not at the same instruction count on the two, so the traces cannot be expected to
  agree past that point.

## How long it takes

| step | clocks | model | QEMU |
|---|---|---|---|
| to the small shell | about 29 million | about 25 s | under a second |
| to the busybox prompt | about 100 million | about 1.5 minutes | 1 to 2 s |
| `hpmstat ls /` | about 2 million | a couple of seconds | instant |

The model retires about 1 to 1.2 million instructions per second. Measured on the busybox boot:

- Compiler and Verilator options (`-march=native`, `--x-assign fast`) buy about 10 %, not worth the loss of
  a portable binary.
- RAM size makes no difference (4 MiB or 16 MiB run at the same speed), and a faster uart
  (`CPB=16`) does not shorten the boot either: it is about 100 million instructions of kernel work
  (memory setup, the initramfs unpack, driver probing) and every one of them is simulated.
- A profile shows the time in Verilator's evaluation of the clocked and the combinational logic of the whole
  soc, three or so passes per clock. Getting much faster means changing the RTL (smaller always blocks, fewer
  loops over arrays) or simulating less, for example booting once and saving the state. Neither is done.

Use QEMU for day to day work and the model when the question is about the core itself.

## Findings (things that were not obvious)

| finding | detail |
|---|---|
| user mode is required | `ret_from_exception` tells a user trap from a kernel trap by `mstatus.MPP`. With `MPP` stuck at machine, the first `ecall` from `init` died with `Oops - environment call from M-mode`. k0 now has U-mode, `ecall` from U is cause 8 |
| no `C`, no bit-manip | the kernel is built for `rv32ima`. `zbb`, `zba`, `zicboz` are on by default and were turned off |
| `/dev/console` | the initramfs needs the node, or `init` starts with no stdin or stdout |
| misaligned access | the kernel probes and emulates it. k0 traps on misaligned loads and stores, which costs one trap at boot |
| 8 MiB is not enough | `binfmt_flat` needs one contiguous block for a task's text, data and stack. busybox is 730 KiB. After the kernel and cpio the 8 MiB ram had no 1 MiB free block, `-ENOMEM`. 16 MiB works |
| the uart needs a FIFO | a 16450 holds one byte and overruns when the sender does not wait. k0 has the 16550A FIFOs and `compatible = "ns16550a"` |
| Buildroot needs a clean `PATH` | empty entries in `PATH` or `LD_LIBRARY_PATH` make it stop. `buildroot/build.sh` removes them |
| Buildroot 2025.02 can do NOMMU rv32 | `BR2_riscv_custom` with `RVI RVM RVA` only, no `RVF RVD`, no MMU, `BR2_BINFMT_FLAT`: uClibc-ng and `elf2flt` build and work |
| the bFLT loader needs a-priori ram | binaries are not demand paged. Every process is copied in whole, so process count times size is the ram bill |

## Known gaps

- PMP is in the hardware (`CHIP.md`) but Linux's M-mode build only opens everything with it. User tasks can
  still overwrite kernel memory until the kernel sets per-task regions.
- No S-mode, no supervisor interrupts. The kernel runs in M-mode, which Linux supports only without an MMU.
- Misaligned accesses trap, emulation is in software.
- No block device, no network, no second hart.
- Not tried on hardware: the clock, memory (a 16 MiB array), timing closure of the core path (the core is not pipelined; divides take 34 clocks).
