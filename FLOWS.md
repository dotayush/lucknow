# end to end flows: digital, analog, mixed signal

All commands assume `source eda.sh` (from the repository root) first; it reads `.env`, see `README.md`. Tool locations are in `TOOLS.md`.
Process: SkyWater sky130. Wulff's blocks use `sky130B` (a few, like `lelo_*`, use `sky130A`); the LibreLane digital flow
uses `sky130A` (`sky130_fd_sc_hd` cells). Both variants come from the one PDK install.

Status marks: **[verified]** ran on this machine, **[untested]** the recommended route, not run yet.
Re-run every check with `./eda.sh verify <new empty dir>` (add `--gui` for the window checks, `--full` for the long runs).

## 0. setup and sanity

```bash
cp .env.example .env            # once: set EDA, the tools directory
./eda.sh install                # idempotent: installs what is missing under $EDA
source eda.sh
make -v | head -1               # must resolve to $EDA/tools/bin/make
magic --version                 # 8.3.684
./eda.sh verify $EDA/scratch/verify-$(date +%m%d%H%M)   # a new dir every time, nothing is deleted
```

`make` here is a shim that forces bash. Wulff's Makefiles use `echo -e`; under dash that writes a
literal `-e` into Tcl scripts and DRC reports a false FAIL. Without `eda.sh` sourced, use `make SHELL=/bin/bash ...`.
`PDK_ROOT` has no trailing slash on purpose: `//` starts a comment for ngspice older than 40.

## 1. analog (opamps, ADCs, DACs) **[verified]**

Wulff's flow: xschem schematic, ngspice simulation, Magic layout, then DRC, LVS, extraction, post-layout sim.

```bash
cd $AICEX/ip && cicconf clone --https          # fetch the ip repos (once)
cd $AICEX/ip/<block>/work                      # e.g. rply_ex0_sky130nm; work from a copy, see the note below

xschem ../design/<LIB>/<CELL>.sch              # 1. schematic (GUI)
make xsch                                      # 2. netlist -> xsch/<CELL>.spice
magic -d 24BIT -rcfile $PDK_ROOT/sky130B/libs.tech/magic/sky130B.magicrc ../design/<LIB>/<CELL>.mag   # 3. layout (GUI)
make gds                                       # 4. gds/<CELL>.gds
make drc                                       # 5. Magic DRC: "DRC OK"
make cdl; make xlvs                            # 6. LVS vs schematic: "CORRECT" (make cdl first; xlvs without it fails)
make lpe                                       # 7. parasitics -> lpe/<CELL>_lpe.spi
make kdrc                                      # 8. optional: the PDK's KLayout rule deck, report in drc/<CELL>_drc.xml
cd ../sim/<CELL> && MPLBACKEND=Agg make typical     # 9. simulate; etc, mc, tfs for corners. VIEW=Sch or Lay
```

- `MPLBACKEND=Agg`: `tran.py` plots with matplotlib and otherwise opens a window and waits for you to close it,
  so a script run hangs.
- `magic -d 24BIT` opens the GUI (needs `wish`, present). `-d XR` is not accepted by 8.3.684. Magic's GUI runs under `wish`.
- `make cdl` before `make xlvs`: without the CDL Netgen cannot read the schematic side and the result is a false INCORRECT.
- New block: copy `rply_ex0_sky130nm` as a template (its README is a step by step tutorial) and change `LIB` and `CELL`
  in `work/Makefile`.
- **Work in a copy.** The flows write into `work/`, `design/` and `sim/` of the clone. `cp -aL` a block to a new directory
  (the `-L` matters: `tech/` is a relative symlink) and put a link to `ciccreator` next to it if it needs one.

**Generated layouts (ciccreator).** `$AICEX/ip/ciccreator` is built (`make compile`, Qt6 from the system) and
`make ip` in a block's `work/` regenerates its Magic cells. For `sun_tr_sky130nm` that gives 59 cells, all DRC OK.

View the GDS without a GUI (renders with the PDK's layer colours):

```bash
cat > render.py <<'PY'
import pya
lv = pya.LayoutView(); lv.load_layout(gds, True); lv.load_layer_props(lyp); lv.max_hier(); lv.zoom_fit(); lv.save_image(out, 1200, 800)
PY
klayout -zz -nc -r render.py -rd gds=gds/<CELL>.gds -rd lyp=$PDK_ROOT/sky130B/libs.tech/klayout/tech/sky130B.lyp -rd out=layout.png
```

### What was checked, and what it showed

| block | check | result |
|---|---|---|
| `rply_ex0` (current mirror) | gds, Magic DRC, xschem netlist, LVS, extraction | all pass; LVS CORRECT |
| `rply_ex0` | KLayout `sky130B_mr.drc`, 256 rule categories | 0 violations (agrees with Magic) |
| `rply_ex0` | Lay typical simulation | 21.7600 uA, his 2024 file 21.7597 uA; vgs 0.62035 V in both |
| `rply_ex0` | 8 corners (ss/ff/sf/fs, hot/cold), extracted layout | within 0.005 uA (0.02 %) of his 2024 file |
| `rply_ex0` | GUIs | magic, xschem, klayout (render) all open and show the right layout |
| `sun_tr` generated library (ciccreator) | Magic DRC, 59 cells | 59/59 OK |
| `sun_tr` leaf cells | standalone LVS | 31 match, 28 do not (gates and switches, body ties); identical on his committed layouts |
| `sun_sar9b` (9 bit SAR ADC) | committed layout: DRC, LVS | DRC OK, LVS CORRECT |
| `sun_pll` (PLL) | committed layout: DRC on 11 cells, LVS | DRC 11/11 OK; top `SUN_PLL` LVS CORRECT (use `make cdl xlvs CELL=SUN_PLL`, the top is hand drawn); 8 of 10 leaf cells match, `LPF` and `LSCORE` do not (internal net names, body tie) |
| `lelo_gr02` (oscillator, 150 x 95 um) | DRC, LVS, extraction | DRC OK, LVS CORRECT at the top (his own checklvs) |

Caveats found while checking:

- **Leaf cells fail standalone LVS by design.** The ciccreator netlist has separate `BULKN`/`BULKP` pins that the
  layout does not wire inside the cell (body ties come from tap cells). Composite cells and the top level match.
  His committed layouts give the same split, so this is his library, not the install.
- **A regenerated SAR ADC fails pin matching** (`D<0>`, `VREF`, ...), while the committed one is LVS CORRECT. `make ip`
  with the current ciccreator and cicpy writes different files (for example `magscale 1 2`, not `1 1`). Use the committed
  layout, or pin the tool versions, before relying on `make ip` for the SAR.
- **His 2022 `Sch_typical` numbers (21.76 uA) are stale and cannot be reproduced** with any tool combination tried:
  ngspice 39, 45.2 and 47 give 20.84 uA for the schematic on PDK builds from 2022-11, 2022-12, 2025-07 and 2026-04,
  with either corner name (`Att`, `Ktt`). His 2024 *extracted layout* results reproduce to four digits, so compare against
  `tran_Lay_*` files dated 2024 or later, not the 2022 `tran_Sch_*` files.
- **Oscillator frequency** (`lelo_gr02`) is about 5 % above his committed April 2026 result and leakage about 14 % lower,
  while the DC current agrees to 0.1 %. Not caused by the tools: the result is the same with ngspice 45.2 and 47, with
  PDK builds from 2025-07 and 2026-04, and with Magic 8.3.684 and current master (the extracted netlists are byte
  identical). His layout files (`LELO_GR02`, `OSCILLATOR`, `COMPARATOR`) were edited on 2026-07-21 ("Fixed GR02 lvs/drc",
  "Fixed ports/labels"), after the April results were committed, so the layout I simulated is not the one behind those
  numbers. That is the likely reason but it is **not proven**: simulating the April layout itself in this flow does not
  oscillate (the `.meas` windows fail), so I could not reproduce the April numbers from the April sources.

## 2. digital (RTL to GDSII) with LibreLane

LibreLane runs Yosys, OpenROAD, Magic (DRC, GDS), Netgen (LVS) and KLayout from a Nix store
(`$EDA/nixroot`), through `bwrap`; no Docker, no root. `librelane`, `openroad`, `klayout` and `sta` on `PATH` are wrappers
around `nixrun`. Any other tool from that store: `nixrun yosys ...`, `nixrun magic ...`.

```bash
# toolchain check **[verified, native, no terminal needed]**: full flow on a tiny design, ends with "Smoke test passed."
librelane --pdk-root $LIBRELANE_PDK_ROOT --smoke-test

# RTL checks before physical design **[verified]**
# from core/l0: shared.sv signext alu decoder regfile csrfile control (l0_core, no memory); l0.sv adds the memories for simulation
verilator --lint-only -Wall -Wno-fatal <those files plus memory.sv l0.sv> --top-module control
# yosys needs the slang front end: its own reader drops `import isa_shared::*` and gives wrong counts
yosys -p "plugin -i slang; read_slang --top l0_core <those files>; synth -top l0_core"

# the real run **[verified: clean DRC, LVS, antenna and XOR; timing in core/l0/librelane/RUNS.md]**
core/l0/librelane/run.sh t<N> '{"CLOCK_PERIOD": 44}'   # the slow corner, delay cells and l0.sdc come from .env (PDK_FAMILY)
# results: <run>/final/{gds,lef,def,nl,sdc,metrics.json} and reports for DRC, LVS, antenna, STA
core/l0/librelane/segments.sh core/l0/librelane/runs/t<N>/final    # delay of each piece of the cycle, from a finished run
core/l0/librelane/screen.sh <new_dir>                              # preview an RTL change by synthesis alone, about a minute
./eda.sh view klayout|openroad|magic <file>                          # look at a result; klayout loads the layer names and the 3D view
```

What `core/l0/librelane` holds and why (details: `RUNS.md`, `TIMING.md` there):

1. `l0_core` is the top (memories outside, ports for fetch and data). A core with no outputs synthesizes to nothing.
2. `l0.sdc` replaces the flow's generic constraint (20% of the clock on every port), which hides the real path. It models the memory as an
   access time and cuts the cycle at the ports.
3. `config.json`: `DESIGN_NAME`, `VERILOG_FILES`, `CLOCK_PORT`, `CLOCK_PERIOD`, utilisation, and the cells kept out of buffering.
4. each run is stored under `$EDA/scratch` and linked into `runs/`; once recorded in `RUNS.md` its folder is deleted (about 1.8 GB each).

`soc/k0` is not ready for this: its ram and rom are behavioral arrays that would become thousands of flip-flops.

## 3. mixed signal **[verified up to signoff; see the result below]**

A real analog block (`LELO_GR02`, the oscillator from `lelo_gr02_sky130a`) was placed as a macro in a small digital design
and taken through LibreLane. The demo scripts are not kept in the repository (they are in git history, commit `e78ade9` and earlier,
under `eda/ms_demo/`); the steps below are what they did.

```bash
# 1. analog block, from its work/ directory (so its .magicrc is used): lef and gds
#    load ../design/<LIB>/<CELL>.mag ; lef write <CELL>.lef -hide ; gds write <CELL>.gds
magic -noconsole -dnull export.tcl

# 2. make the macro acceptable to the digital flow (all three were needed)
#    a. lef: Magic writes every pin as USE SIGNAL. Set the rails to POWER and GROUND in the .lef.
#    b. gds: LibreLane needs a PR boundary. Magic does not write one. Add layer 235/4 over the cell bbox
#       (klayout -zz -nc -r addpr.py with a pya script: top.shapes(ly.layer(235,4)).insert(pya.Box(top.bbox()))).
#    c. pdn: the default macro grid only connects on met4/met5. Copy LibreLane's pdn_cfg.tcl, add
#         add_pdn_connect -grid macro -layers "met3 met4"
#       and point "PDN_CFG" at it. Use a strap pitch (PDN_VPITCH, PDN_HPITCH ~30) that puts straps across the rails.

# 3. digital top with the macro as a blackbox (signal pins only), config.json with MACROS, PDN_MACRO_CONNECTIONS,
#    DIE_AREA, then:
librelane --pdk-root $LIBRELANE_PDK_ROOT --pdk sky130A --run-tag ms config.json
```

`config.json` keys that mattered: `MACROS` (`gds`, `lef`, `instances` with `location` and `orientation`),
`PDN_MACRO_CONNECTIONS` (`"osc_i VPWR VGND VDD_1V8 VSS"`: instance, core power net, core ground net, macro power pin,
macro ground pin), `PDN_CFG`, `PDN_VPITCH` and `PDN_HPITCH`, `DIE_AREA`.

**Result [verified]:** `ms_demo` (330 x 260 um, 15.9k cells incl. fill, a counter that powers up the oscillator and a
synchroniser that counts its output) closes with every signoff count at 0: Magic DRC 0, KLayout DRC 0, LVS errors 0
(device and net differences 0), antenna 0, routing DRC 0, Magic/KLayout streamout XOR 0, setup and hold violations 0 at a
50 ns clock (worst setup slack +37 ns, hold +0.11 ns). The final GDS has the analog macro inside it.
The run takes about 10 minutes.

Two things that went wrong first, and are worth knowing:

- With the macro 25 um from the core edge, 1673 Magic DRC errors (N-well taps, latch-up `LU.2`/`LU.3`) and 65 LVS errors
  appeared in the leftover strip (filler cells with floating N-wells). None were inside the analog block. Place the macro so
  no narrow strip is left between it and the core edge.
- A rail pin on met3 gets no power connection from the default PDN (see step 2c above); without it the flow stops at
  the IR drop check with `PSM-0069`, and with too coarse a strap pitch the macro rail is still "unconnected".

Not done: the analog block was not re-simulated inside the digital design, and `ms_demo` has no timing model of the macro
(STA treats it as a blackbox), so this proves the physical flow, not the mixed-signal behaviour.

System simulation of the two domains together is **[untested]**: verilog for the digital part and a behavioural model of the
analog block in Verilator or iverilog, or ngspice on the analog block with a behavioural stimulus.

## 4. housekeeping

```bash
df -h / /home "$EDA"   # keep / above 5 GB
```

Run each check in a new directory under `$EDA/scratch`; do not delete run directories to save
space without asking (a standing rule: no recursive deletes).
