#!/usr/bin/env bash
# mixed signal demo: Wulff's LELO_GR02 oscillator (analog, magic) as a macro inside a small digital design (librelane).
# usage: ms_demo/run.sh <new_dir>      ~10 minutes. Nothing is overwritten: <new_dir> must not exist or be empty.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../env.sh"
D=${1:?usage: run.sh <new_dir>}
[ -z "$(ls -A "$D" 2>/dev/null)" ] || { echo "$D is not empty"; exit 1; }
mkdir -p "$D/design"
cp "$HERE/ms_demo.v" "$HERE/config.json" "$HERE/pdn_cfg.tcl" "$HERE/addpr.py" "$D/design/"

# 1. analog block: lef and gds from its magic layout (a copy, so aicex is untouched)
cp -aL "$AICEX/ip/lelo_gr02_sky130a" "$D/blk"
cat > "$D/design/export.tcl" <<TCL
load ../design/LELO_GR02_SKY130A/LELO_GR02.mag
select top cell
lef write $D/design/LELO_GR02.lef -hide
gds write $D/design/LELO_GR02.gds
quit -noprompt
TCL
( cd "$D/blk/work" && magic -noconsole -dnull "$D/design/export.tcl" >"$D/magic_export.log" 2>&1 )

# 2. make the macro acceptable to the digital flow
python3 -I - "$D/design/LELO_GR02.lef" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(PIN VSS\n\s+DIRECTION INPUT ;\n\s+USE )SIGNAL", r"\1GROUND", s)      # magic writes every pin as SIGNAL
s = re.sub(r"(PIN VDD_1V8\n\s+DIRECTION INPUT ;\n\s+USE )SIGNAL", r"\1POWER", s)
open(p, "w").write(s)
PY
cp "$D/design/LELO_GR02.gds" "$D/design/LELO_GR02.nopr.gds"
klayout -zz -nc -r "$D/design/addpr.py" -rd src="$D/design/LELO_GR02.nopr.gds" -rd dst="$D/design/LELO_GR02.gds"   # librelane needs a PR boundary (235/4)

# 3. the flow
( cd "$D/design" && librelane --pdk-root "$LIBRELANE_PDK_ROOT" --pdk sky130A --run-tag ms config.json ) >"$D/librelane.log" 2>&1 || true

# 4. verdict
python3 -I - "$D/design/runs/ms/final/metrics.json" <<'PY'
import json, sys
try: m = json.load(open(sys.argv[1]))
except Exception as e: print("FAIL no metrics:", e); sys.exit(1)
want = {"magic__drc_error__count": 0, "klayout__drc_error__count": 0, "design__lvs_error__count": 0,
        "antenna__violating__nets": 0, "route__drc_errors": 0, "timing__setup_vio__count": 0, "timing__hold_vio__count": 0}
bad = {k: m.get(k) for k, v in want.items() if m.get(k) != v}
for k in want: print(f"{k:34s} {m.get(k)}")
print("PASS" if not bad else f"FAIL {bad}"); sys.exit(1 if bad else 0)
PY
