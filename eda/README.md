# eda

Setup, environment and checks for the open silicon flow (sky130) used for l0, k0 and analog blocks.
The tools themselves live on the external SSD (`/media/ayush/secondary/eda`), not in this repo.

| file | what |
|---|---|
| `env.sh` | `source` it: PATH, `PDK_ROOT` (sky130A and sky130B), `LIBRELANE_PDK_ROOT`, `AICEX` |
| `setup.sh` | idempotent: venv with librelane, the `make` shim, `nixrun` and its wrappers |
| `make.shim` | `make` that always uses bash (Wulff's makefiles use `echo -e`, which dash prints literally) |
| `nixrun.sh` | runs a tool from the nix store on the SSD through `bwrap` (OpenROAD, KLayout, Yosys, Magic, Netgen, librelane) |
| `verify.sh` | checks everything from a clean environment; `--gui` opens the windows, `--full` also runs `ms_demo` |
| `ms_demo/` | mixed signal demo: an analog oscillator as a macro in a digital design, through LibreLane to a signoff-clean GDS |

```bash
source eda/env.sh
eda/verify.sh /media/ayush/secondary/eda/scratch/verify-$(date +%m%d%H%M)    # a new directory every time
eda/ms_demo/run.sh /media/ayush/secondary/eda/scratch/ms-$(date +%m%d%H%M)  # about 10 minutes, ends with PASS
```

Flows and their verified status: `docs/eda_flows.md`. Tool locations: `docs/tool_paths.md` (not tracked by git).
Run every flow in a copy under `scratch/`; nothing here deletes anything.
