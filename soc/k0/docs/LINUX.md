# Linux on k0

What runs, how to build it, how to use it, and what was learned. The chip itself is described in
`CHIP.md`, the plan this followed (with its findings) in `PLAN.md`.

## What works

A Linux 6.12.112 kernel without an MMU boots on k0 in a Verilator model and gives a busybox shell on the
uart. You can type at it from your terminal. Pipes, `$(( ))`, `/proc` and several processes at once work.
The same kernel image boots unchanged on QEMU's `virt` machine and prints the same command output, so
QEMU is the reference.

Not done: a real FPGA or chip (no clock, memory controller or board files), PMP (user tasks can write
kernel memory), any block device (the root filesystem is an archive inside the kernel image).

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
Without root, build `bc` and `rsync` from source into a directory and pass it as `BC_PATH=`.

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

### Reference run on QEMU

```
QEMU=<dir with qemu-system-riscv32> QEMU_DATA=<share/qemu dir> ./linux/qemu.sh
```

Without root, `apt-get download qemu-system-riscv qemu-system-common qemu-system-data` and
`dpkg -x` each into one directory works (what was done here). QEMU makes its own device tree. Command
output is identical to the model's; the boot log differs (timestamps, `base_baud`, the PLIC size) because
the hardware description does.

## How long it takes

| step | clocks | Verilator time |
|---|---|---|
| to the small shell | about 29 million | about 20 s |
| to the busybox prompt | about 92 million | about 1 minute |
| one typed line of 10 characters | about 25 thousand | instant |

The model retires about 1.7 million instructions per second. The uart is 256 clocks per bit, so a
character takes about 2560 clocks on the line.

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

- No PMP: a user task can overwrite kernel memory. Fine for a demo, not for isolation.
- No S-mode, no supervisor interrupts. The kernel runs in M-mode, which Linux supports only without an MMU.
- Misaligned accesses trap, emulation is in software.
- No block device, no network, no second hart.
- Not tried on hardware: the clock, memory (a 16 MiB array), timing closure of a single-cycle path.
