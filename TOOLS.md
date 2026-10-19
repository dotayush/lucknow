# tools

What `eda.sh` puts on `PATH`, and where each tool lives. `$EDA` is the tools directory from `.env` (`cp .env.example .env`,
set `EDA`); nothing in this repository names a machine specific path.

```bash
source eda.sh        # environment (PATH, PDK_ROOT, AICEX, ...)
./eda.sh install     # sets up what is missing under $EDA; skips what is there
./eda.sh verify <new dir>
```

## Layout of `$EDA`

| what | path |
|---|---|
| tools prefix: wrappers, magic, netgen, xschem | `$EDA/tools` (`bin`, `lib`) |
| python venv: `ciel` (PDK manager), `klayout` module, `cicpy`, `cicsim`, `cicconf`, `cicspi`, `cicwave` | `$EDA/venv` |
| sources and build logs | `$EDA/src` |
| PDK, librelane/ciel layout (`LIBRELANE_PDK_ROOT`), open_pdks build 2025-07-14, 2.2 GB | `$EDA/pdk` |
| PDK, what `PDK_ROOT` points at (holds the variants, no trailing slash) | `$EDA/pdk/ciel/$PDK_FAMILY/versions/$PDK_VERSION` (sky130: `sky130A`, `sky130B`; gf180mcu: `gf180mcuA` to `D`) |
| aicex (`AICEX`) | `$EDA/src/aicex` |
| nix store of the librelane image (472 packages, 5.6 GB) | `$EDA/nixroot` (`store`, `image.env`) |
| OSS CAD Suite 2025-08-18 | `$EDA/oss_cad` |
| RISC-V bare metal toolchain (gcc 15.1.0, rv32im, ilp32, newlib), 2.4 GB | `$EDA/riscv32` |
| scratch for runs and checks (one new directory per run, never reused) | `$EDA/scratch` |

Other PDK families install next to the first under `$EDA/pdk/ciel/` (see The PDK below). Older PDK builds, ngspice 39 and 45.2
and magic master were used once to investigate stale reference numbers (`FLOWS.md`) and are not kept; rebuild them with
`ciel enable --pdk-root <dir> <hash>` or from the git tags if needed.

## Tools

| tool | version | path |
|---|---|---|
| make (shim: forces `SHELL=/bin/bash`, then `/usr/bin/make`) | 4.4.1 | `$EDA/tools/bin/make` |
| magic | 8.3.684 (aicex's pin) | `$EDA/tools/bin/magic` |
| netgen | 1.5.324 (aicex's pin) | `$EDA/tools/bin/netgen` |
| ext2spice, ext2sim | with magic | `$EDA/tools/bin/` |
| cic (ciccreator, Qt6 build, used by `make ip`) | 0.1.5+ | `$AICEX/ip/ciccreator/bin/cic` |
| cicpy, cicsim, cicconf, cicspi, cicwave | editable installs from `src/` | `$EDA/venv/bin/` |
| ciel (PDK manager) | 2.6.1 | `$EDA/venv/bin/ciel` |
| python `klayout` module (no GUI) | 0.30.12 | in `$EDA/venv` |
| librelane (wrapper to nixrun) | 3.0.16 | `$EDA/tools/bin/librelane` |
| openroad, klayout, sta (wrappers to nixrun) | OpenROAD 2026-02-17, KLayout 0.30.7 | `$EDA/tools/bin/` |
| nixrun (bwrap: mounts the store at `/nix/store`, clears `LD_LIBRARY_PATH`; `NIXRUN_GL=1` adds the host OpenGL for the KLayout 3D view) | | `$EDA/tools/bin/nixrun` |
| tools inside the nix store, run as `nixrun <tool>` | yosys 0.62, magic 8.3.623, netgen 1.5.316, verilator 5.044, iverilog | `$EDA/nixroot/store` |
| yosys (with the slang plugin, nextpnr) | 0.56+141 | `$EDA/oss_cad/bin/yosys` |
| verilator | 5.039 | `$EDA/oss_cad/bin/verilator` |
| iverilog, vvp | | `$EDA/oss_cad/bin/` |
| gtkwave (the OSS CAD copy needs glibc 2.38 and may not start) | | `$EDA/oss_cad/bin/gtkwave` |
| xschem | 3.4.7 (aicex's pin) | `$EDA/tools/bin/xschem` |
| ngspice | 47 | `/usr/local/bin/ngspice` (system; `EXTRA_PATH`), or built into `$EDA/tools/bin` by `install` when no ngspice 47 is on `PATH` |
| riscv32-unknown-elf-gcc, objcopy, nm (bare metal) | 15.1.0 | `$EDA/riscv32/bin/` (built from riscv-gnu-toolchain 2025.08.08 by `install riscv`, about an hour) |

## The PDK

`.env` sets `PDK_FAMILY` and `eda.sh` derives the rest; the flow scripts name no PDK. Several families can be installed side by side
under `$EDA/pdk/ciel/` and the choice is only the variable.

| | sky130 (default) | gf180mcu |
|---|---|---|
| `PDK_VERSION` (ciel, open_pdks build, the one LibreLane 3.0.16 pins) | `8afc8346...` (2025-07-14), 2.2 GB | `54435919...`, 3.6 GB |
| `PDK_DIGITAL` / `PDK_ANALOG` | `sky130A` / `sky130B` | `gf180mcuD` / `gf180mcuD` |
| `STD_CELL_LIBRARY` | `sky130_fd_sc_hd` | `gf180mcu_fd_sc_mcu7t5v0` |
| `PDK_SLOW`, `PDK_TYP` | `ss_100C_1v60`, `tt_025C_1v80` | `ss_125C_4v50`, `tt_025C_5v00` |
| `PDK_DELAY_CELLS` kept out of buffering | `clkdlybuf*`, `dlymetal*` | none |
| tested | everything | the l0 flow (`run.sh`, `screen.sh`); the analog flow is sky130 only |

`ihp-sg13g2` (IHP SG13G2, 130 nm BiCMOS, `PDK_VERSION` `c4b8b4e5...`) is in the table too and goes through the same l0 flow. `PDK_FO4_PS` (inverter FO4 delay, `core/l0/librelane/fo4.sh`) scales the `l0.sdc` budgets, so a PDK's constraints are the same in gate delays; a new family needs it in `.env`.

`./eda.sh install pdk` fetches the selected one. Switching `PDK_FAMILY` in a shell that already sourced `eda.sh` keeps the old `PDK_*` values: open a new shell. Only the digital flow is PDK independent: the analog blocks of aicex are sky130
(`verify` skips them for another family). Timing budgets in `l0.sdc` are assumptions made for sky130 (scaled by FO4 on another PDK).

`.env` has two more settings: `EDA` (required) and `EXTRA_PATH`, a `:` separated list appended to `PATH` for tools that are not under
`$EDA` (ngspice). `install` needs `git`, `curl`, `python3-venv`, a C/C++ toolchain, Tcl/Tk and X11
development packages, Qt6 (for ciccreator) and `bubblewrap`; it prints the ones it cannot find. Getting the nix store needs
Docker once (`install nixroot` pulls the librelane image, copies `/nix/store` out and leaves the image for you to remove).

## Where files live in aicex

`$AICEX/ip/<block>/` has `design/` (`.sch`, `.mag`), `work/` (run `make` here), `tech/`, `sim/`, `cic/`.
Do not run flows in these directories; `cp -aL` a block into `$EDA/scratch` and run there (`tech/` is a relative symlink).

## Not installed

- qemu-system-riscv32 on `PATH` (the k0 scripts fetch their own)
- nothing from the LibreLane image is missing; its tools run from the nix store (see nixrun)

## Disk

Builds, PDK copies and runs all live under `$EDA`. A LibreLane run is about 1.8 GB, a PDK copy 2 GB.
`./eda.sh verify` fails a check with less than 5 GB free on `/`, `/home` or `$EDA`.
