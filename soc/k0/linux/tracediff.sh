#!/usr/bin/env bash
# runs the kernel for the first N instructions on the model and on QEMU (with the same device tree) and
# compares the pc of every instruction, up to the first difference, and says where in the kernel it is.
#   N=2000000 ./linux/tracediff.sh        (QEMU=<dir> QEMU_DATA=<dir> as for qemu.sh)
# the two are expected to part ways once something depends on time (the first timer interrupt, a delay loop):
# QEMU's clock is not the model's clock.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/out}
N=${N:-2000000}
KVER=6.12.112
VMLINUX=${VMLINUX:-${WORK:-$HOME/personal/k0-linux}/src/linux-$KVER/vmlinux}
IMG=${IMAGE:-Image.busybox}
tmp=$(mktemp -d)
Q=${QEMU:+$QEMU/}qemu-system-riscv32
[ -n "${QEMU_DATA:-}" ] && L=(-L $QEMU_DATA) || L=()

$HERE/../sim/obj/Vsoc +image=$OUT/$IMG +image=$OUT/k0.dtb@807f0000 +max_cycles=$((N + N / 8)) +trace=$tmp/sim.trc > /dev/null 2>&1 || true
# one instruction per translation block: every "Trace" line of the exec log is one retired instruction
{ timeout ${QEMU_SECS:-10} $Q -M virt -cpu rv32 -m 16M -smp 1 -nographic -bios none "${L[@]}" -dtb $OUT/k0.dtb -kernel $OUT/$IMG \
    -accel tcg,one-insn-per-tb=on -d exec,nochain -D /dev/stdout 2>/dev/null || true; } \
  | grep -a '^Trace' | head -n $((N + 200)) > $tmp/qemu.log || true

python3 -I - $tmp/sim.trc $tmp/qemu.log $VMLINUX $N <<'PY'
import re, subprocess, sys
simf, qf, vm, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
sim = [int(l, 16) for l in open(simf)]
q = []
for l in open(qf, errors="replace"):
    m = re.search(r"\[[0-9a-f]+/([0-9a-f]+)/", l)
    if m: q.append(int(m.group(1), 16))
# both start by running their own boot code in rom: compare from the first instruction in ram
def from_ram(t):
    for i, pc in enumerate(t):
        if pc >= 0x80000000: return t[i:]
    return []
sim, q = from_ram(sim), from_ram(q)
# a wait loop runs a different number of times on each side (the model's uart takes 256 clocks per bit,
# QEMU's is instant): every iteration of a short loop is dropped in both traces
def collapse(t, window=128):
    # coming back to an instruction visited within the last `window` means an iteration ended: drop it,
    # so a wait loop is the same short path whatever the number of times it went round
    o, pos = [], {}
    for pc in t:
        p = pos.get(pc)
        if p is not None and p < len(o) and o[p] == pc and len(o) - p <= window:
            del o[p:]
        pos[pc] = len(o)
        o.append(pc)
    return o
sim, q = collapse(sim), collapse(q)
# QEMU does not log the instruction that follows a store to a device (it re-translates the block), so a
# single missing instruction is not a difference. they are counted and reported.
i = j = skipped = 0
m = len(sim)
while i < m and j < len(q):
    if sim[i] == q[j]:
        i += 1; j += 1
    elif i + 1 < len(sim) and sim[i + 1] == q[j]:
        i += 1; skipped += 1
    else:
        break
same = i
syms = []
try:
    out = subprocess.run(["nm", "-n", vm], capture_output=True, text=True).stdout
    # nm for the target: use the riscv32 binutils if present
except Exception:
    out = ""
def where(pc):
    import bisect
    if not syms: return ""
    k = bisect.bisect_right([s[0] for s in syms], pc) - 1
    return f"{syms[k][1]}+{pc - syms[k][0]:#x}" if k >= 0 else ""
tc = "/opt/riscv32/bin/riscv32-unknown-elf-nm"
try:
    out = subprocess.run([tc, "-n", vm], capture_output=True, text=True).stdout
    for l in out.splitlines():
        p = l.split()
        if len(p) == 3 and p[1] in "tTwW": syms.append((int(p[0], 16), p[2]))
except Exception:
    pass
print(f"after reducing wait loops: model {len(sim)}, qemu {len(q)} instructions in ram")
done = (i >= m) or (j >= len(q))
print(f"same pc sequence for the first {same} instructions ({skipped} missing from the qemu log)" + (", end of both traces" if done else ""))
if not done:
    for k in range(-4, 4):
        mark = "   <-- first difference" if k == 0 else ""
        if 0 <= i + k < len(sim) and 0 <= j + k < len(q):
            print(f"  [{i + k}] model {sim[i + k]:08x} {where(sim[i + k]):40s} qemu {q[j + k]:08x} {where(q[j + k])}{mark}")
PY
rm -f $tmp/sim.trc $tmp/qemu.log; rmdir $tmp
