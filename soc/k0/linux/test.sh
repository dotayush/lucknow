#!/usr/bin/env bash
# boots the kernel on the verilator model, types a few commands at the
# shell and checks the answers. ./linux/build.sh and ./sim/build.sh
# first. takes a couple of minutes.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
printf 'echo hello from k0\nmul 12345 678\nfib 25\nmul 7777 9999\n' > $tmp/in
RX=$tmp/in STOP="77762223|end Kernel panic" MAX=${MAX:-400000000} $HERE/run.sh > $tmp/out 2>&1
fail=0
for want in "Run /init as init process" "init is running in user space" "hello from k0" "8369910" "75025" "77762223"; do
  if grep -q -- "$want" $tmp/out; then echo "ok:   $want"; else echo "FAIL: $want"; fail=1; fi
done
grep -q "Kernel panic" $tmp/out && { echo "FAIL: kernel panic"; fail=1; }
[ $fail -eq 0 ] && echo "PASS" || { echo "FAIL (log: $tmp/out)"; exit 1; }
rm -f $tmp/in $tmp/out; rmdir $tmp
