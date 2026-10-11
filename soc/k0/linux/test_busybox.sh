#!/usr/bin/env bash
# boots the busybox image (buildroot/build.sh and busybox.sh first, and sim/build.sh), types commands at its
# shell and checks the answers. about 2 minutes: the boot is about 100 million clocks, the session 20 million more.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/out}
tmp=$(mktemp -d)
printf 'echo busybox-ok\nuname -m\nls /bin | head -3\nexpr 6 \\* 7\ncat /proc/cpuinfo | grep -c isa\nhpmstat ls /\necho done-$((6*7))\n' > $tmp/in
$HERE/../sim/obj/Vsoc +image=$OUT/Image.busybox +image=$OUT/k0.dtb@807f0000 +max_cycles=${MAX:-900000000} \
  "+stop_on=done-42|end Kernel panic" +rx=$tmp/in +rx_delay=${RX_DELAY:-135000000} +rx_gap=2 > $tmp/out 2>&1
fail=0
for want in "Run /init as init process" "~ # " "^busybox-ok" "^riscv32" "^arch" "^42" "^2[[:space:]]*$" "^instructions" "^done-42"; do
  if grep -q -- "$want" $tmp/out; then echo "ok:   $want"; else echo "FAIL: $want"; fail=1; fi
done
grep -q "Kernel panic" $tmp/out && { echo "FAIL: kernel panic"; fail=1; }
[ $fail -eq 0 ] && echo "PASS" || { echo "FAIL (log: $tmp/out)"; exit 1; }
rm -f $tmp/in $tmp/out; rmdir $tmp
