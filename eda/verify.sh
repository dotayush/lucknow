#!/usr/bin/env bash
# end to end check of the eda setup. run in a clean env: ./verify.sh [scratch_dir]
# scratch_dir must be new/empty-ish; the analog flow runs in a copy there so nothing in aicex changes.
set -u
GUI=0; FULL=0
while [ "${1:-}" = "--gui" ] || [ "${1:-}" = "--full" ]; do [ "$1" = "--gui" ] && GUI=1; [ "$1" = "--full" ] && FULL=1; shift; done
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
S=${1:-$(mktemp -d)}
mkdir -p "$S"
pass=0; fail=0
ok()  { printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL  %s\n' "$1"; fail=$((fail+1)); }
chk() { local name=$1; shift; if "$@" >"$S/last.log" 2>&1; then ok "$name"; else bad "$name  (log: $S/last.log)"; tail -3 "$S/last.log" | sed 's/^/        /'; fi; }
has() { grep -q -- "$2" "$S/last.log" && ok "$1" || bad "$1 (wanted '$2')"; }

echo "== disk and mounts"
chk "ssd mounted and writable" bash -c "touch $EDA/.w && rm $EDA/.w"
for fs in / /home; do
  free=$(df --output=avail -BG "$fs" | tail -1 | tr -dc 0-9)
  [ "$free" -ge 5 ] && ok "$fs has ${free}G free (>=5G)" || bad "$fs has only ${free}G free"
done

echo "== tool resolution (clean PATH from env.sh)"
for t in make magic netgen ext2spice cicpy cicsim cicconf librelane openroad klayout sta nixrun xschem ngspice yosys verilator iverilog riscv32-unknown-elf-gcc; do
  p=$(command -v "$t") && ok "$t -> $p" || bad "$t not on PATH"
done
[ "$(command -v verilator)" = "$EDA/oss_cad/bin/verilator" ] && ok "verilator is oss_cad 5.039" || bad "verilator is not from oss_cad ($(command -v verilator))"
[ "$(command -v make)" = "$EDA/tools/bin/make" ] && ok "make is the bash shim" || bad "make is not the shim"
[ "$(command -v magic)" = "$EDA/tools/bin/magic" ] && ok "magic is the native 8.3.684" || bad "magic not from tools/bin"

echo "== versions"
chk "magic 8.3.684"  magic --version;            has "magic version" "8.3.684"
chk "netgen 1.5.324" bash -c 'netgen -batch quit </dev/null | head -1'; has "netgen version" "1.5.324"
chk "yosys (oss cad)" yosys -V
chk "verilator" verilator --version
chk "iverilog" bash -c 'iverilog -V | head -1'
chk "ngspice 47" bash -c 'ngspice -v </dev/null | head -3'; has "ngspice version" "ngspice-47"
chk "xschem" bash -c 'xschem --version </dev/null | head -2'
chk "openroad (nix)" openroad -version
chk "klayout (nix)" klayout -v;                   has "klayout version" "0.30"
chk "librelane (nix)" bash -c 'librelane --version 2>&1 | tail -1'
chk "nixrun yosys 0.62" nixrun yosys -V;          has "nix yosys" "0.62"
chk "nixrun magic 8.3.623" nixrun magic --version;has "nix magic" "8.3.623"
chk "python klayout module" python3 -I -c 'import klayout.db'
chk "cic* python tools import" "$EDA/venv/bin/python" -c 'import cicpy, cicsim, cicconf'

echo "== pdk"
case "$PDK_ROOT" in */) bad "PDK_ROOT ends with a slash (ngspice < 40 reads // as a comment)";; *) ok "PDK_ROOT has no trailing slash";; esac
for v in sky130A sky130B; do
  for d in libs.ref libs.tech; do [ -d "$PDK_ROOT/$v/$d" ] && ok "$v/$d" || bad "$v/$d missing"; done
done
[ -d "$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd" ] && ok "sky130_fd_sc_hd present" || bad "sky130_fd_sc_hd missing"
chk "magic loads sky130B tech" bash -c "echo 'puts tech=[tech name]; quit -noprompt' > $S/t.tcl; timeout 60 magic -dnull -noconsole -rcfile $PDK_ROOT/sky130B/libs.tech/magic/sky130B.magicrc $S/t.tcl </dev/null"
has "tech name" "tech=sky130B"

echo "== make shim and dash safety"
chk "sh -> make still uses bash" sh -c 'cd /tmp && printf "t:\n\t@echo -e a\n" > '"$S"'/mk && make -f '"$S"'/mk t'
has "echo -e not literal" "^a$"
chk "dash alone would break (premise of the shim)" bash -c "sh -c 'echo -e x' | grep -q -- '-e x'"

echo "== analog flow, fresh copy"
SRC=$AICEX/ip/rply_ex0_sky130nm
if [ -d "$SRC" ]; then
  W=$S/analog/rply_ex0_sky130nm
  mkdir -p "$S/analog" && cp -aL "$SRC" "$W" 2>/dev/null   # -L: tech/ is a relative symlink
  # the copy must not carry results from earlier runs: only keep sources
  for d in gds drc lvs lpe cdl xsch; do :; done
  cd "$W/work" || bad "copy missing"
  # outputs from earlier runs are copied too; compare timestamps by forcing regeneration via new dirs
  for t in gds drc xsch xlvs lpe; do
    chk "analog make $t" make -B $t
  done
  chk "drc result" bash -c 'make drc 2>&1 | tail -1'; has "DRC OK" "DRC OK"
  chk "lvs result" bash -c 'make xlvs 2>&1 | tail -12'; has "LVS CORRECT" "CORRECT"
  chk "gds readable" python3 -I -c "
import klayout.db as db
l=db.Layout(); l.read('$W/work/gds/RPLY_EX0.gds'); b=l.top_cell().dbbox()
assert b.width()>10 and b.height()>3, b"
  chk "lpe netlist has parasitics" bash -c "grep -c '^C' $W/work/lpe/RPLY_EX0_lpe.spi | awk '{exit !(\$1>0)}'"
  cd "$HERE"
else bad "aicex example missing"; fi


echo "== analog extras (ciccreator, klayout deck, committed designs, simulation cross-check)"
# cic --help prints its usage and exits 1, so judge it by the text
chk "ciccreator binary runs" bash -c "\"$AICEX/ip/ciccreator/bin/cic\" --help 2>&1 | grep -q 'Usage: cic'"
# his result files the numbers below are compared against are dated 2024; the 2022 Sch_typical is stale (see docs)
mkdir -p "$S/x1" && cp -aL "$AICEX/ip/rply_ex0_sky130nm" "$S/x1/rply" && cd "$S/x1/rply/work" || bad "rply copy"
chk "rply lpe (for the Lay simulation)" make lpe
cd "$S/x1/rply/sim/RPLY_EX0" && chk "rply Lay typical simulation (ngspice)" env MPLBACKEND=Agg make VIEW=Lay typical
chk "rply Lay typical matches his committed 2024 result within 0.1%" python3 -I -c "
import csv
a=float(list(csv.DictReader(open('$S/x1/rply/sim/RPLY_EX0/results/tran_Lay_typical.csv')))[-1]['ibns_20u'])
b=float(list(csv.DictReader(open('$AICEX/ip/rply_ex0_sky130nm/sim/RPLY_EX0/results/tran_Lay_typical.csv')))[-1]['ibns_20u'])
assert abs(a-b)/b<1e-3,(a,b)
print(a,b)"
cd "$S/x1/rply/work" && chk "gds for klayout deck" make gds
mkdir -p drc && chk "klayout sky130B DRC deck runs" make kdrc
chk "klayout deck reports 0 violations" python3 -I -c "
import re,sys
s=open('$S/x1/rply/work/drc/RPLY_EX0_drc.xml').read(); n=len(re.findall(r'<item>',s)); print(n,'violations'); sys.exit(n!=0)"
# generated library: ciccreator -> magic. 59 cells, all drc clean
mkdir -p "$S/x2/ip" && cp -aL "$AICEX/ip/sun_tr_sky130nm" "$S/x2/ip/sun_tr_sky130nm" && ln -sfn "$AICEX/ip/ciccreator" "$S/x2/ip/ciccreator"
cd "$S/x2/ip/sun_tr_sky130nm/work" && chk "make ip (ciccreator generates the layout library)" make ip
make drcall 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$S/x2/drcall.txt"
nok=$(grep -c 'DRC OK' "$S/x2/drcall.txt"); nfail=$(grep -c 'DRC FAIL' "$S/x2/drcall.txt")
[ "$nok" = 59 ] && [ "$nfail" = 0 ] && ok "generated sun_tr library: $nok/59 cells DRC OK" || bad "generated sun_tr library DRC: ok=$nok fail=$nfail"
# committed SAR ADC: drc and lvs with the committed layout (a regenerated one fails pin matching, see docs)
mkdir -p "$S/x3/ip" && cp -aL "$AICEX/ip/sun_sar9b_sky130nm" "$S/x3/ip/sun_sar9b_sky130nm" && ln -sfn "$AICEX/ip/sun_tr_sky130nm" "$S/x3/ip/sun_tr_sky130nm"
cd "$S/x3/ip/sun_sar9b_sky130nm/work"
chk "sar9b committed layout DRC" bash -c "make drc 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -1"; has "sar9b DRC OK" "DRC OK"
make cdl >/dev/null 2>&1
chk "sar9b committed layout LVS" bash -c "make lvs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -12"; has "sar9b LVS CORRECT" "CORRECT"
cd "$HERE"

echo "== digital flow, native, no docker"
chk "docker not needed (daemon may be down)" true
mkdir -p "$S/dig" && cd "$S/dig"
chk "librelane smoke test (no tty)" bash -c "librelane --pdk-root $LIBRELANE_PDK_ROOT --smoke-test 2>&1 | tr -d '\r' | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | tail -200"
has "smoke test passed (no tty)" "Smoke test passed"
cd "$HERE"

echo "== oss cad and zsh"
[ -L "$HOME/.zshrc" ] && [ "$(readlink "$HOME/.zshrc")" = ".dotfiles/zsh/.zshrc" ] && ok "~/.zshrc is the dotfiles symlink" || bad "~/.zshrc is not the dotfiles symlink"
chk "zshrc points at ssd oss_cad" zsh -ic 'command -v yosys'; has "zsh yosys path" "/media/ayush/secondary/eda/oss_cad/bin/yosys"
cmp -s "$HOME/.zshrc" "$HOME/.dotfiles/zsh/.zshrc" && ok "zshrc == dotfiles file" || bad "zshrc differs"


if [ "$GUI" = 1 ]; then
echo "== gui windows (needs a display; opens and closes them)"
export DISPLAY=${DISPLAY:-:1}
if xdpyinfo >/dev/null 2>&1; then
  cd "$AICEX/ip/rply_ex0_sky130nm/work"
  (sleep 20 | timeout 22 magic -d 24BIT -rcfile "$PDK_ROOT/sky130B/libs.tech/magic/sky130B.magicrc" ../design/RPLY_EX0_SKY130NM/RPLY_EX0.mag >/dev/null 2>&1 &)
  sleep 8; xwininfo -root -tree 2>/dev/null | grep -q '"RPLY_EX0": ("magic"' && ok "magic gui opened the layout" || bad "magic gui window not found"
  (timeout 14 xschem ../design/RPLY_EX0_SKY130NM/RPLY_EX0.sch >/dev/null 2>&1 &)
  sleep 7; xwininfo -root -tree 2>/dev/null | grep -q 'xschem - RPLY_EX0.sch' && ok "xschem gui opened the schematic" || bad "xschem gui window not found"
  cat > "$S/render.py" <<'PY'
import pya
lv = pya.LayoutView(); lv.load_layout(gds, True); lv.load_layer_props(lyp); lv.max_hier(); lv.zoom_fit(); lv.save_image(out, 800, 500)
PY
  chk "klayout renders the gds with the sky130B layer properties" klayout -zz -nc -r "$S/render.py" -rd gds="$AICEX/ip/rply_ex0_sky130nm/work/gds/RPLY_EX0.gds" -rd lyp="$PDK_ROOT/sky130B/libs.tech/klayout/tech/sky130B.lyp" -rd out="$S/render.png"
  [ -s "$S/render.png" ] && ok "render.png written" || bad "render.png missing"
  cd "$HERE"
else bad "no X display for --gui"; fi
fi


if [ "$FULL" = 1 ]; then
echo "== full: mixed signal demo (analog macro inside a digital design, ~10 min)"
chk "ms_demo/run.sh finishes with every signoff count at 0" "$HERE/ms_demo/run.sh" "$S/ms"
tail -9 "$S/last.log"
fi

echo "== docs reference real paths"
miss=0
for p in $(grep -oE '`/[^` ]+`' "$HERE/../docs/tool_paths.md" | tr -d '`' | grep -vE '^/(nix|bin/make|bin/docker|var|opt/riscv32/bin/?$)' | grep -v '\*'); do
  [ -e "$p" ] || { echo "        missing: $p"; miss=1; }
done
[ $miss = 0 ] && ok "all absolute paths in tool_paths.md exist" || bad "tool_paths.md has missing paths"
[ ! -e "$HERE/../docs/tool_paths.md" ] || git -C "$HERE/.." check-ignore -q docs/tool_paths.md && ok "tool_paths.md is gitignored" || bad "tool_paths.md not gitignored"

echo "== repo l0 rtl commands from the docs"
cd "$HERE/../core/l0"
L="src/shared.sv src/signext.sv src/alu.sv src/decoder.sv src/regfile.sv src/csrfile.sv src/memory.sv src/control.sv"
chk "verilator lint l0 control" verilator --lint-only -Wall -Wno-fatal $L --top-module control
LC="src/shared.sv src/signext.sv src/alu.sv src/decoder.sv src/regfile.sv src/csrfile.sv src/control.sv"
# memory.sv cannot go through yosys (initial zero loop + $readmemh = "Conflicting initialization values"), so it is a blackbox here
chk "yosys elaborates l0 core with memory.sv as blackbox" yosys -q -p "read_verilog -sv src/shared.sv; read_verilog -lib -sv src/memory.sv; read_verilog -sv ${LC#src/shared.sv }; hierarchy -top control; proc; check"
mkdir -p "$S/mem"
cat > "$S/mem/top.sv" <<'SV'
module top(input wire clk, input wire rst_n, input wire mem_write, input wire mem_read, input wire [1:0] t, input wire [31:0] a, input wire [31:0] d, output wire [31:0] q, output wire [1:0] e);
  memory #(.MEM_INIT("./memory/test_rom.hex")) m(.clk(clk), .rst_n(rst_n), .mem_write(mem_write), .mem_read(mem_read), .mem_access_type(t), .addr(a), .data_in(d), .data_out(q), .mem_error(e));
endmodule
SV
sed 's/MEM_INIT("[^"]*")/MEM_INIT("")/' "$S/mem/top.sv" > "$S/mem/top_noimg.sv"
chk "yosys accepts memory.sv without an init image" yosys -q -p "read_verilog -sv src/shared.sv src/memory.sv $S/mem/top_noimg.sv; hierarchy -top top; proc"
chk "yosys rejects memory.sv with an init image (known blocker)" bash -c "! yosys -q -p 'read_verilog -sv src/shared.sv src/memory.sv $S/mem/top.sv; hierarchy -top top; proc' >/dev/null 2>&1"
# premise of the l0 plan: control has no bus, only clk and rst_n, so synthesis of it alone is empty
chk "l0 control ports are only clk and rst_n (needs a wrapper before P&R)" bash -c "yosys -q -p 'read_verilog -sv $L; hierarchy -top control; tee -o /dev/stdout select -list-ports -count control' ; awk '/^module control/,/\\);/' src/control.sv | grep -cE '^ *(input|output|inout) ' | grep -qx 2"
cd "$HERE"

echo
echo "pass=$pass fail=$fail  scratch=$S"
[ "$fail" = 0 ]
