#!/bin/bash
# fo4.sh   process yardstick for the PDK in .env: the delay of an inverter driving four inverters (FO4) at the slow corner and at the typical one,
# and the area of a minimum NAND2, from the liberty files. TIMING.md uses them to compare PDKs: l0's segments in FO4 and its area in NAND2 equivalents.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../../../eda.sh"
pre=${PDK_DRIVING_CELL%inv_2}   # cell name prefix of the library, with its separator
w=$(mktemp -d "${TMPDIR:-/tmp}/fo4-XXXXXX"); cd "$w"
for corner in "$PDK_SLOW" "$PDK_TYP"; do
  lib=${PDK_LIB_SLOW%$PDK_SLOW.lib}$corner.lib
  python3 - "$lib" "$pre" > nl_$corner.v <<'PY'
import re,sys
lib,pre=sys.argv[1:3]
t=open(lib).read()
def cell(name):
    m=re.search(r'cell\s*\(\s*"?%s"?\s*\)'%re.escape(name),t); return t[m.start():m.start()+200000]
inv=cell(pre+'inv_1')
pd=re.findall(r'pin\s*\(\s*"?(\w+)"?\s*\)\s*\{[^{}]{0,400}?direction\s*:\s*"?(input|output)',inv)
i=[p for p,d in pd if d=='input'][0]; o=[p for p,d in pd if d=='output'][0]
n=6
print('module fo4(input a, output y);')
print('wire '+','.join(f'n{k}' for k in range(1,n))+';')
N=lambda k: 'y' if k==n else f'n{k}'
c=pre+'inv_1'
print(f'{c} s0(.{i}(a),.{o}(n1));')
for k in range(1,n):
    print(f'{c} s{k}(.{i}(n{k}),.{o}({N(k+1)}));')
    for d in range(3): print(f'{c} d{k}_{d}(.{i}(n{k}),.{o}());')
for d in range(4): print(f'{c} e{d}(.{i}(y),.{o}());')
print('endmodule')
PY
  cat > sta_$corner.tcl <<TCL
read_liberty $lib
read_verilog nl_$corner.v
link_design fo4
create_clock -name v -period 1000
set_input_delay 0 -clock v [get_ports a]
set_output_delay 0 -clock v [get_ports y]
set p [lindex [find_timing_paths -path_delay max] 0]
puts "arrival [expr [\$p data_arrival_time]*1e9]"
exit
TCL
  d=$(sta -no_init -exit sta_$corner.tcl 2>&1 | awk '/^arrival/{print $2}')
  # six stages (s0 to s5), each driving four inverter inputs; the first has an ideal input
  echo "$corner  FO4 $(python3 -c "print(round($d/6*1000,1))") ps"
done
a=$(python3 - "$PDK_LIB_SLOW" "$pre" <<'PY'
import re,sys
t=open(sys.argv[1]).read()
for n in ('nand2_1','nand2_2'):
    m=re.search(r'cell\s*\(\s*"?%s"?\s*\)'%re.escape(sys.argv[2]+n),t)
    if m:
        a=re.search(r'\barea\s*:\s*([\d.]+)',t[m.end():m.end()+400000])
        print(a.group(1)); break
PY
)
echo "nand2 area $a um2"
echo "work dir $w"
