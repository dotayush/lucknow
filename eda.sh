#!/usr/bin/env bash
# the one file for the open silicon tools (analog, mixed signal and digital flows; the PDK is chosen in .env).
#
#   source eda.sh                        put every tool on PATH (settings come from .env next to this file)
#   ./eda.sh                             menu: install, verify, shell, view
#   ./eda.sh install [step ...]          set up what is missing under $EDA, skip what is there
#   ./eda.sh verify [--gui] [dir]
#   ./eda.sh shell                       a new shell with the tools on PATH
#   ./eda.sh view klayout|openroad|magic <file> [sdc]
#
# .env (copy .env.example) says where the tools live. nothing here deletes anything.

# ---- environment: runs when sourced and when executed -------------------------------------------------------------
if [ -n "${ZSH_VERSION:-}" ]; then
  _lk_self=${(%):-%x}
  case $ZSH_EVAL_CONTEXT in *:file*) _lk_sourced=1;; *) _lk_sourced=0;; esac
else
  _lk_self=${BASH_SOURCE[0]}
  if [ "${BASH_SOURCE[0]}" != "$0" ]; then _lk_sourced=1; else _lk_sourced=0; fi
fi
LUCKNOW=$(cd "$(dirname "$_lk_self")" && pwd)
export LUCKNOW

_lk_eda=${EDA:-}   # an EDA already in the environment wins over .env, e.g. EDA=/tmp/x ./eda.sh install
if [ -f "$LUCKNOW/.env" ]; then set -a; . "$LUCKNOW/.env"; set +a; fi
[ -n "$_lk_eda" ] && EDA=$_lk_eda
unset _lk_eda
if [ -z "${EDA:-}" ]; then
  echo "eda.sh: EDA is not set. cp $LUCKNOW/.env.example $LUCKNOW/.env and point EDA at the tools directory" >&2
  if [ "$_lk_sourced" = 1 ]; then return 1; else exit 1; fi
fi
export EDA

# the PDK. .env picks the family (PDK_FAMILY), the rest follows from this table and can be overridden in .env.
# every flow script reads these variables, none names a PDK itself. a family that is not in the table needs all of them in .env.
#   PDK_VERSION        ciel version (open_pdks build) to install
#   PDK_DIGITAL        variant the digital flow (librelane) runs on;  PDK_ANALOG: variant the analog flow (aicex, magic) runs on
#   STD_CELL_LIBRARY   standard cell library the digital flow maps to
#   PDK_SLOW, PDK_TYP  liberty corners (<process>_<temp>_<voltage>): the slow one timing is judged in, the typical one for viewing
#   PDK_DRIVING_CELL, PDK_DRIVING_PIN   inverter that drives the inputs in the SDC and its output pin (defaults: <library>__inv_2, Y)
#   PDK_FO4_PS         delay of an inverter driving four inverters at PDK_SLOW, in ps (core/l0/librelane/fo4.sh). l0.sdc scales its budgets with it
#   PDK_DELAY_CELLS    delay cells (comma separated patterns, without the library prefix) the resizer must not use as buffers
PDK_FAMILY=${PDK_FAMILY:-sky130}
case $PDK_FAMILY in
  sky130)   : "${PDK_FO4_PS:=131.3}" "${PDK_VERSION:=8afc8346a57fe1ab7934ba5a6056ea8b43078e71}" "${PDK_DIGITAL:=sky130A}" "${PDK_ANALOG:=sky130B}" \
              "${STD_CELL_LIBRARY:=sky130_fd_sc_hd}" "${PDK_SLOW:=ss_100C_1v60}" "${PDK_TYP:=tt_025C_1v80}" "${PDK_DELAY_CELLS:=clkdlybuf*,dlymetal*}" ;;
  gf180mcu) : "${PDK_FO4_PS:=414.1}" "${PDK_VERSION:=54435919abffb937387ec956209f9cf5fd2dfbee}" "${PDK_DIGITAL:=gf180mcuD}" "${PDK_ANALOG:=gf180mcuD}" \
              "${STD_CELL_LIBRARY:=gf180mcu_fd_sc_mcu7t5v0}" "${PDK_SLOW:=ss_125C_4v50}" "${PDK_TYP:=tt_025C_5v00}" "${PDK_DELAY_CELLS:=}" "${PDK_DRIVING_PIN:=ZN}" ;;
  ihp-sg13g2) : "${PDK_FO4_PS:=98.9}" "${PDK_VERSION:=c4b8b4e5e7a05f375cca3815d51b3a37721fbf5c}" "${PDK_DIGITAL:=ihp-sg13g2}" "${PDK_ANALOG:=ihp-sg13g2}" \
              "${STD_CELL_LIBRARY:=sg13g2_stdcell}" "${PDK_SLOW:=slow_1p08V_125C}" "${PDK_TYP:=typ_1p20V_25C}" "${PDK_DELAY_CELLS:=}" \
              "${PDK_DRIVING_CELL:=sg13g2_inv_2}" ;;
esac
for _lk_v in PDK_VERSION PDK_DIGITAL PDK_ANALOG STD_CELL_LIBRARY PDK_SLOW PDK_TYP; do
  eval "_lk_x=\${$_lk_v:-}"
  if [ -z "$_lk_x" ]; then
    echo "eda.sh: PDK_FAMILY=$PDK_FAMILY is not in the table in eda.sh: set $_lk_v (and the other PDK_* variables) in .env" >&2
    if [ "$_lk_sourced" = 1 ]; then return 1; else exit 1; fi
  fi
done
unset _lk_v _lk_x
export PDK_FO4_PS PDK_FAMILY PDK_VERSION PDK_DIGITAL PDK_ANALOG STD_CELL_LIBRARY PDK_SLOW PDK_TYP PDK_DELAY_CELLS
export PDK_DRIVING_CELL=${PDK_DRIVING_CELL:-${STD_CELL_LIBRARY}__inv_2}       # what drives the inputs in the SDC, and its output pin
export PDK_DRIVING_PIN=${PDK_DRIVING_PIN:-Y}
export PDK_ROOT=$EDA/pdk/ciel/$PDK_FAMILY/versions/$PDK_VERSION               # no trailing slash: '//' starts a comment for ngspice < 40
# the slow corner liberty and the LEFs of the standard cell library, found by pattern because the PDKs name them differently (empty until the PDK is installed)
unset PDK_LIB_SLOW PDK_TECH_LEF PDK_CELL_LEF
_lk_r=$PDK_ROOT/$PDK_DIGITAL/libs.ref/$STD_CELL_LIBRARY
for _lk_f in "$_lk_r/lib/${STD_CELL_LIBRARY}__$PDK_SLOW.lib" "$_lk_r/lib/${STD_CELL_LIBRARY}_$PDK_SLOW.lib"; do [ -f "$_lk_f" ] && PDK_LIB_SLOW=$_lk_f; done
_lk_f=$(ls "$_lk_r/techlef" 2>/dev/null | grep '__nom.tlef$' | head -1); [ -n "$_lk_f" ] && PDK_TECH_LEF=$_lk_r/techlef/$_lk_f
[ -z "${PDK_TECH_LEF:-}" ] && { _lk_f=$(ls "$_lk_r/lef" 2>/dev/null | grep '_tech.lef$' | head -1); [ -n "$_lk_f" ] && PDK_TECH_LEF=$_lk_r/lef/$_lk_f; }
[ -f "$_lk_r/lef/$STD_CELL_LIBRARY.lef" ] && PDK_CELL_LEF=$_lk_r/lef/$STD_CELL_LIBRARY.lef
unset _lk_r _lk_f
export PDK_LIB_SLOW PDK_TECH_LEF PDK_CELL_LEF
export LIBRELANE_PDK_ROOT=$EDA/pdk                                            # ciel layout, for: librelane --pdk-root
export PDK=$PDK_ANALOG                                                        # what aicex's makefiles read
export AICEX=$EDA/src/aicex
export LD_LIBRARY_PATH=$EDA/tools/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
# oss_cad ahead of /bin: verilator 5.039, not the distribution's
export PATH=$EDA/tools/bin:$EDA/venv/bin:$EDA/oss_cad/bin:$EDA/riscv32/bin:$PATH
# tools installed outside $EDA (ngspice): appended, so a shell that already has them is unchanged
for _lk_d in $(printf '%s' "${EXTRA_PATH:-}" | tr ':' ' '); do
  case ":$PATH:" in *":$_lk_d:"*) ;; *) PATH=$PATH:$_lk_d;; esac
done
export PATH
unset _lk_d

if [ "$_lk_sourced" = 1 ]; then unset _lk_self _lk_sourced; return 0; fi

# ---- from here on the file is run, not sourced ---------------------------------------------------------------------
set -u
ROOT=$LUCKNOW
die() { echo "eda.sh: $*" >&2; exit 1; }

# ==== install ======================================================================================================
NIX_IMAGE=ghcr.io/librelane/librelane:3.0.16
OSS_CAD_TAG=2025-08-18
MAGIC_TAG=8.3.684
NETGEN_TAG=1.5.324
NGSPICE_TAG=ngspice-47
XSCHEM_TAG=3.4.7
RISCV_TAG=2025.08.08   # riscv-gnu-toolchain: gcc 15.1.0, bare metal rv32im / ilp32, newlib
J=$(nproc 2>/dev/null || echo 4)

# step <name> <test that succeeds when present> <function>
step() {
  local name=$1 have=$2 fn=$3
  if (eval "$have") >/dev/null 2>&1; then printf 'present   %s\n' "$name"; return; fi
  printf 'installing %s\n' "$name"
  if (set -e; $fn); then printf 'done      %s\n' "$name"; else printf 'FAILED    %s\n' "$name"; INSTALL_FAILED=1; fi
}

# the wrappers are rewritten on every install (they are small and hold no state).
# nixrun finds $EDA from its own location when EDA is not set.
do_wrappers() {
  mkdir -p "$EDA"/tools/bin
  cat > "$EDA/tools/bin/nixrun" <<'EOF'
#!/bin/bash
# run a command with the librelane toolchain (openroad, yosys, magic, netgen, klayout, librelane) from the nix store
# in $EDA/nixroot (copied once out of the librelane image). no root: bwrap mounts the store at /nix/store.
# NIXRUN_GL=1 lets the tool reach the host's NVIDIA OpenGL libraries (links in $EDA/tools/glhost), for the KLayout 3D view.
# usage: nixrun openroad -version
EDA=${EDA:-$(cd "$(dirname "$0")/../.." && pwd)}
STORE=$EDA/nixroot/store
[ -d "$STORE" ] || { echo "nixrun: $STORE missing (eda.sh install nixroot)" >&2; exit 1; }
args=(--unshare-user --die-with-parent --tmpfs /)
for d in /usr /bin /sbin /lib /lib64 /etc /opt /var /run /home /media /mnt /srv; do
  [ -e "$d" ] && args+=(--bind "$d" "$d")
done
args+=(--unsetenv LD_LIBRARY_PATH --unsetenv LD_PRELOAD ${NIXRUN_GL:+--setenv LD_LIBRARY_PATH "$EDA/tools/glhost" --setenv __GLX_VENDOR_LIBRARY_NAME nvidia} --bind "$STORE" /nix/store --dev-bind /dev /dev --proc /proc --bind /sys /sys --bind /tmp /tmp)
# image env: PATH with every tool, python path, certs. HOME stays yours.
while IFS= read -r l; do
  case $l in PATH=*) args+=(--setenv PATH "${l#PATH=}:/usr/bin:/bin");; esac
  case $l in NIX_PYTHONPATH=*|LANG=*|LC_ALL=*|LC_CTYPE=*) args+=(--setenv "${l%%=*}" "${l#*=}");; esac
done < "$EDA/nixroot/image.env"
exec bwrap "${args[@]}" "$@"
EOF
  cat > "$EDA/tools/bin/make" <<'EOF'
#!/bin/bash
# make that always uses bash. wulffern's makefiles write tcl with `echo -e`, which dash (debian's /bin/sh)
# prints literally, so drc/lvs/gds fail or, worse, report a false DRC FAIL.
# SHELL on the command line wins over the makefile and is passed on to sub-makes.
exec /usr/bin/make SHELL=/bin/bash "$@"
EOF
  for t in openroad klayout sta librelane; do
    printf '#!/bin/bash\nexec "$(dirname "$0")/nixrun" %s "$@"\n' "$t" > "$EDA/tools/bin/$t"
  done
  chmod +x "$EDA"/tools/bin/{nixrun,make,openroad,klayout,sta,librelane}
}

do_venv() {
  mkdir -p "$EDA/src"
  python3 -m venv "$EDA/venv"
  "$EDA/venv/bin/pip" install --quiet --upgrade pip
  "$EDA/venv/bin/pip" install --quiet ciel klayout   # ciel fetches the pdk, klayout is the python module (no GUI)
  for r in cicpy cicsim cicconf; do [ -d "$EDA/src/$r" ] || git clone -q https://github.com/wulffern/$r.git "$EDA/src/$r"; done
  "$EDA/venv/bin/pip" install --quiet -e "$EDA/src/cicpy"
  "$EDA/venv/bin/pip" install --quiet -r "$EDA/src/cicsim/requirements.txt" -e "$EDA/src/cicsim"
  "$EDA/venv/bin/pip" install --quiet -e "$EDA/src/cicconf"
}

do_oss_cad() {   # yosys, verilator, iverilog, gtkwave, nextpnr, the slang plugin
  local f=oss-cad-suite-linux-x64-${OSS_CAD_TAG//-/}.tgz
  mkdir -p "$EDA/oss_cad" "$EDA/src"
  curl -fL -o "$EDA/src/$f" "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$OSS_CAD_TAG/$f"
  tar -xzf "$EDA/src/$f" -C "$EDA/oss_cad" --strip-components=1
}

do_pdk() {
  "$EDA/venv/bin/ciel" enable --pdk-family "$PDK_FAMILY" --pdk-root "$EDA/pdk" "$PDK_VERSION"
}

build_git() {   # build_git <name> <url> <tag> [configure args]: autotools project from a git tag into $EDA/tools
  local name=$1 url=$2 tag=$3; shift 3
  mkdir -p "$EDA/src"
  [ -d "$EDA/src/$name" ] || git clone -q "$url" "$EDA/src/$name"
  git -C "$EDA/src/$name" checkout -q "$tag"
  cd "$EDA/src/$name"
  [ -x configure ] || { libtoolize --force >/dev/null 2>&1 || true; ./autogen.sh > "$EDA/src/$name-autogen.log" 2>&1; }
  ./configure --prefix="$EDA/tools" "$@" > "$EDA/src/$name-configure.log" 2>&1
  make -j"$J" > "$EDA/src/$name-make.log" 2>&1
  make install > "$EDA/src/$name-install.log" 2>&1
}
do_magic()   { build_git magic  https://github.com/RTimothyEdwards/magic.git  "$MAGIC_TAG"; }
do_netgen()  { build_git netgen https://github.com/RTimothyEdwards/netgen.git "$NETGEN_TAG"; }
do_ngspice() { build_git ngspice-src https://git.code.sf.net/p/ngspice/ngspice "$NGSPICE_TAG" --with-x --enable-xspice --enable-openmp --enable-pss --enable-cider --with-readline=yes --disable-debug; }
do_riscv() {   # about an hour and 8 GB of build space; the result is 2.4 GB
  mkdir -p "$EDA/src"
  [ -d "$EDA/src/riscv-gnu-toolchain" ] || git clone -q --branch "$RISCV_TAG" --depth 1 https://github.com/riscv-collab/riscv-gnu-toolchain.git "$EDA/src/riscv-gnu-toolchain"
  cd "$EDA/src/riscv-gnu-toolchain"
  git submodule update --init --depth 1 gcc binutils newlib gdb > "$EDA/src/riscv-submodules.log" 2>&1
  mkdir -p build && cd build
  ../configure --prefix="$EDA/riscv32" --with-arch=rv32im --with-abi=ilp32 --with-isa-spec=20191213 --disable-multilib > "$EDA/src/riscv-configure.log" 2>&1
  make -j"$J" > "$EDA/src/riscv-make.log" 2>&1
}
do_xschem()  { build_git xschem https://github.com/StefanSchippers/xschem.git "$XSCHEM_TAG"; }

do_aicex() {
  mkdir -p "$EDA/src"
  git clone --recursive --depth 1 https://github.com/wulffern/aicex.git "$AICEX"
  ( cd "$AICEX/ip" && PATH="$EDA/venv/bin:$PATH" cicconf clone --https )   # the ip repos (blocks, ciccreator), once
}

do_ciccreator() {   # the layout generator behind `make ip`; Qt6 from the system
  export PATH="$EDA/tools/bin:$EDA/venv/bin:$PATH"
  cd "$AICEX/ip/ciccreator" && make compile -j"$J" > "$EDA/src/ciccreator-build.log" 2>&1
}

do_nixroot() {   # the nix store of the librelane image: openroad, klayout, yosys, magic, netgen, librelane. needs docker once.
  command -v docker >/dev/null || { echo "docker is needed once to copy the nix store out of $NIX_IMAGE (then it can be removed)"; return 1; }
  mkdir -p "$EDA/nixroot/store"
  docker pull -q "$NIX_IMAGE" >/dev/null
  docker run --rm --entrypoint /root/.nix-profile/bin/tar "$NIX_IMAGE" -C /nix/store -cf - . | tar -xf - -C "$EDA/nixroot/store" --no-same-owner
  docker inspect "$NIX_IMAGE" --format '{{range .Config.Env}}{{println .}}{{end}}' > "$EDA/nixroot/image.env"
  echo "the image is no longer needed: docker rmi $NIX_IMAGE"
}

do_glhost() {   # links to the host's NVIDIA OpenGL libraries, for the KLayout 3D view only
  local d=/usr/lib/x86_64-linux-gnu l
  mkdir -p "$EDA/tools/glhost"
  for l in $(ls "$d" | grep -E '^(libGLX_nvidia\.so\.0|libEGL_nvidia\.so\.0|libnvidia-(glsi|tls|glcore|gpucomp|eglcore|glvkspirv)\.so\.[0-9.]+)$'); do
    ln -sf "$d/$l" "$EDA/tools/glhost/$l"
  done
}

missing_packages() {   # builds fail on missing development packages, so name the ones that are not there
  command -v dpkg >/dev/null || return 0
  local p
  for p in git curl python3-venv build-essential tcl-dev tk-dev libx11-dev libcairo2-dev libglu1-mesa-dev m4 csh bison flex libreadline-dev qt6-base-dev libqt6svg6-dev; do
    dpkg -s $p >/dev/null 2>&1 || echo "package not installed: $p"
  done
}

cmd_install() {
  command -v bwrap >/dev/null || echo "note: bwrap is missing (apt install bubblewrap), nixrun needs it"
  mkdir -p "$EDA"/{tools/bin,src,scratch}
  INSTALL_FAILED=0
  local want=" $* "; [ $# = 0 ] && want=" all "
  run() { case "$want" in *" all "*|*" $1 "*) step "$@";; esac; }
  run wrappers 'false' do_wrappers
  run venv     "[ -x '$EDA/venv/bin/ciel' ] && [ -x '$EDA/venv/bin/cicsim' ]" do_venv
  run oss_cad  "[ -x '$EDA/oss_cad/bin/yosys' ]" do_oss_cad
  run pdk      "[ -d '$PDK_ROOT/$PDK_DIGITAL' ] && [ -d '$PDK_ROOT/$PDK_ANALOG' ]" do_pdk
  run magic    "'$EDA/tools/bin/magic' --version 2>&1 | grep -q '^$MAGIC_TAG'" do_magic
  run netgen   "[ -x '$EDA/tools/bin/netgen' ]" do_netgen
  run ngspice  "ngspice -v 2>&1 | grep -q '$NGSPICE_TAG'" do_ngspice
  run xschem   "[ -x '$EDA/tools/bin/xschem' ]" do_xschem
  run riscv    "[ -x '$EDA/riscv32/bin/riscv32-unknown-elf-gcc' ]" do_riscv
  run aicex    "[ -d '$AICEX/ip' ]" do_aicex
  run ciccreator "[ -x '$AICEX/ip/ciccreator/bin/cic' ]" do_ciccreator
  run nixroot  "[ -f '$EDA/nixroot/image.env' ] && [ -d '$EDA/nixroot/store' ]" do_nixroot
  run glhost   "[ -e '$EDA/tools/glhost/libGLX_nvidia.so.0' ] || [ ! -e /usr/lib/x86_64-linux-gnu/libGLX_nvidia.so.0 ]" do_glhost
  echo
  [ "$INSTALL_FAILED" = 0 ] && echo "install finished. next: ./eda.sh verify" || { echo "some steps failed; the logs are in $EDA/src"; missing_packages; return 1; }
}

# ==== view =========================================================================================================
# opens a LibreLane result in a viewer, with layer names (klayout) or the database loaded (openroad).
# openroad -gui takes a Tcl script, not a database: given an .odb it tries to run the binary as Tcl (GUI-0070), so the db is read by a script.
cmd_view() {
  [ $# -ge 2 ] || die "usage: eda.sh view klayout|openroad|magic <file> [sdc]"
  local tool=$1 file sdc=${3:-} sky=$PDK_ROOT/$PDK_DIGITAL
  file=$(readlink -f "$2")
  case $tool in
    klayout)
      # KLAYOUT_PATH makes the PDK macros visible too (menu "Efabless sky130", D25 View = the 3D viewer)
      export KLAYOUT_PATH=$sky/libs.tech/klayout
      export NIXRUN_GL=1   # the nix klayout cannot reach the host graphics driver by itself; the 3D viewer needs OpenGL
      exec klayout -l "$sky/libs.tech/klayout/tech/$PDK_DIGITAL.lyp" "$file" ;;
    openroad)
      local tcl; tcl=$(mktemp "${TMPDIR:-/tmp}/view-XXXXXX.tcl")
      {
        echo "read_db $file"
        echo "read_liberty ${PDK_LIB_SLOW%$PDK_SLOW.lib}$PDK_TYP.lib"
        [ -n "$sdc" ] && echo "read_sdc [file normalize $sdc]"
      } > "$tcl"
      exec openroad -gui "$tcl" ;;
    magic) exec magic -d 24BIT -rcfile "$sky/libs.tech/magic/$PDK_DIGITAL.magicrc" "$file" ;;
    *) die "usage: eda.sh view klayout|openroad|magic <file> [sdc]" ;;
  esac
}

# ==== verify =======================================================================================================
# end to end check of the setup. the analog flow runs in a copy under the given directory, so nothing in aicex changes.
cmd_verify() {
  local GUI=0
  while [ "${1:-}" = "--gui" ]; do GUI=1; shift; done
  local S=${1:-$EDA/scratch/verify-$(date +%m%d%H%M)}
  [ -z "$(ls -A "$S" 2>/dev/null)" ] || die "$S is not empty, give a new directory"
  mkdir -p "$S"
  local pass=0 fail=0
  ok()  { printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
  bad() { printf 'FAIL  %s\n' "$1"; fail=$((fail+1)); }
  chk() { local name=$1; shift; if "$@" >"$S/last.log" 2>&1; then ok "$name"; else bad "$name  (log: $S/last.log)"; tail -3 "$S/last.log" | sed 's/^/        /'; fi; }
  has() { grep -q -- "$2" "$S/last.log" && ok "$1" || bad "$1 (wanted '$2')"; }

  echo "== disk"
  chk "tools directory writable" bash -c "touch '$EDA/.w' && rm '$EDA/.w'"
  local fs free
  for fs in / /home "$EDA"; do
    free=$(df --output=avail -BG "$fs" | tail -1 | tr -dc 0-9)
    [ "$free" -ge 5 ] && ok "$fs has ${free}G free (>=5G)" || bad "$fs has only ${free}G free"
  done

  echo "== tool resolution"
  local t p
  for t in make magic netgen ext2spice cicpy cicsim cicconf librelane openroad klayout sta nixrun xschem ngspice yosys verilator iverilog riscv32-unknown-elf-gcc; do
    p=$(command -v "$t") && ok "$t -> $p" || bad "$t not on PATH"
  done
  [ "$(command -v verilator)" = "$EDA/oss_cad/bin/verilator" ] && ok "verilator is oss_cad 5.039" || bad "verilator is not from oss_cad ($(command -v verilator))"
  [ "$(command -v make)" = "$EDA/tools/bin/make" ] && ok "make is the bash shim" || bad "make is not the shim"
  [ "$(command -v xschem)" = "$EDA/tools/bin/xschem" ] && ok "xschem is under \$EDA" || bad "xschem is not under \$EDA ($(command -v xschem))"
  [ "$(command -v riscv32-unknown-elf-gcc)" = "$EDA/riscv32/bin/riscv32-unknown-elf-gcc" ] && ok "riscv gcc is under \$EDA" || bad "riscv gcc is not under \$EDA"
  [ "$(command -v magic)" = "$EDA/tools/bin/magic" ] && ok "magic is the native 8.3.684" || bad "magic not from tools/bin"

  echo "== versions"
  chk "magic 8.3.684"  magic --version;            has "magic version" "8.3.684"
  chk "netgen 1.5.324" bash -c 'netgen -batch quit </dev/null | head -1'; has "netgen version" "1.5.324"
  chk "yosys (oss cad)" yosys -V
  chk "verilator" verilator --version
  chk "iverilog" bash -c 'iverilog -V | head -1'
  chk "ngspice 47" bash -c 'ngspice -v </dev/null | head -3'; has "ngspice version" "ngspice-47"
  chk "riscv gcc 15.1.0" bash -c 'riscv32-unknown-elf-gcc --version | head -1'; has "riscv gcc version" "15.1.0"
  chk "xschem" bash -c 'xschem --version </dev/null | head -2'
  chk "openroad (nix)" openroad -version
  chk "klayout (nix)" klayout -v;                   has "klayout version" "0.30"
  chk "librelane (nix)" bash -c 'librelane --version 2>&1 | tail -1'
  chk "nixrun yosys 0.62" nixrun yosys -V;          has "nix yosys" "0.62"
  chk "nixrun magic 8.3.623" nixrun magic --version;has "nix magic" "8.3.623"
  chk "python klayout module" python3 -I -c 'import klayout.db'
  chk "cic* python tools import" "$EDA/venv/bin/python" -c 'import cicpy, cicsim, cicconf'

  echo "== pdk ($PDK_FAMILY $PDK_VERSION)"
  case "$PDK_ROOT" in */) bad "PDK_ROOT ends with a slash (ngspice < 40 reads // as a comment)";; *) ok "PDK_ROOT has no trailing slash";; esac
  local v d
  for v in $(printf '%s\n' "$PDK_DIGITAL" "$PDK_ANALOG" | sort -u); do
    for d in libs.ref libs.tech; do [ -d "$PDK_ROOT/$v/$d" ] && ok "$v/$d" || bad "$v/$d missing"; done
  done
  [ -d "$PDK_ROOT/$PDK_DIGITAL/libs.ref/$STD_CELL_LIBRARY" ] && ok "$STD_CELL_LIBRARY present" || bad "$STD_CELL_LIBRARY missing"
  [ -f "$PDK_ROOT/$PDK_DIGITAL/libs.ref/$STD_CELL_LIBRARY/lib/${STD_CELL_LIBRARY}__$PDK_SLOW.lib" ] && ok "slow corner $PDK_SLOW has a liberty file" || bad "no liberty file for $PDK_SLOW"
  chk "magic loads the $PDK_ANALOG tech" bash -c "echo 'puts tech=[tech name]; quit -noprompt' > $S/t.tcl; timeout 60 magic -dnull -noconsole -rcfile $PDK_ROOT/$PDK_ANALOG/libs.tech/magic/$PDK_ANALOG.magicrc $S/t.tcl </dev/null"
  has "tech name" "tech=$PDK_ANALOG"

  echo "== make shim and dash safety"
  chk "sh -> make still uses bash" sh -c 'cd /tmp && printf "t:\n\t@echo -e a\n" > '"$S"'/mk && make -f '"$S"'/mk t'
  has "echo -e not literal" "^a$"
  chk "dash alone would break (premise of the shim)" bash -c "sh -c 'echo -e x' | grep -q -- '-e x'"

  if [ "$PDK_FAMILY" = sky130 ]; then   # aicex's blocks are sky130 only
    echo "== analog flow, fresh copy"
    local SRC=$AICEX/ip/rply_ex0_sky130nm W
    if [ -d "$SRC" ]; then
      W=$S/analog/rply_ex0_sky130nm
      mkdir -p "$S/analog" && cp -aL "$SRC" "$W" 2>/dev/null   # -L: tech/ is a relative symlink
      cd "$W/work" || bad "copy missing"
      for t in gds drc xsch xlvs lpe; do chk "analog make $t" make -B $t; done
      chk "drc result" bash -c 'make drc 2>&1 | tail -1'; has "DRC OK" "DRC OK"
      chk "lvs result" bash -c 'make xlvs 2>&1 | tail -12'; has "LVS CORRECT" "CORRECT"
      chk "gds readable" python3 -I -c "
import klayout.db as db
l=db.Layout(); l.read('$W/work/gds/RPLY_EX0.gds'); b=l.top_cell().dbbox()
assert b.width()>10 and b.height()>3, b"
      chk "lpe netlist has parasitics" bash -c "grep -c '^C' $W/work/lpe/RPLY_EX0_lpe.spi | awk '{exit !(\$1>0)}'"
      cd "$ROOT"
    else bad "aicex example missing"; fi

    echo "== analog extras (ciccreator, klayout deck, committed designs, simulation cross-check)"
    # cic --help prints its usage and exits 1, so judge it by the text
    chk "ciccreator binary runs" bash -c "\"$AICEX/ip/ciccreator/bin/cic\" --help 2>&1 | grep -q 'Usage: cic'"
    # his result files the numbers below are compared against are dated 2024; the 2022 Sch_typical is stale (see FLOWS.md)
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
    local nok nfail
    nok=$(grep -c 'DRC OK' "$S/x2/drcall.txt"); nfail=$(grep -c 'DRC FAIL' "$S/x2/drcall.txt")
    [ "$nok" = 59 ] && [ "$nfail" = 0 ] && ok "generated sun_tr library: $nok/59 cells DRC OK" || bad "generated sun_tr library DRC: ok=$nok fail=$nfail"
    # committed SAR ADC: drc and lvs with the committed layout (a regenerated one fails pin matching, see FLOWS.md)
    mkdir -p "$S/x3/ip" && cp -aL "$AICEX/ip/sun_sar9b_sky130nm" "$S/x3/ip/sun_sar9b_sky130nm" && ln -sfn "$AICEX/ip/sun_tr_sky130nm" "$S/x3/ip/sun_tr_sky130nm"
    cd "$S/x3/ip/sun_sar9b_sky130nm/work"
    chk "sar9b committed layout DRC" bash -c "make drc 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -1"; has "sar9b DRC OK" "DRC OK"
    make cdl >/dev/null 2>&1
    chk "sar9b committed layout LVS" bash -c "make lvs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -12"; has "sar9b LVS CORRECT" "CORRECT"
    cd "$ROOT"

  else echo "== analog flow: skipped, the aicex blocks are sky130 only"; fi

  echo "== digital flow, native"
  mkdir -p "$S/dig" && cd "$S/dig"
  if [ "$PDK_FAMILY" = sky130 ]; then   # the smoke test design is sky130
    chk "librelane smoke test (no tty)" bash -c "librelane --pdk-root $LIBRELANE_PDK_ROOT --smoke-test 2>&1 | tr -d '\r' | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | tail -200"
    has "smoke test passed (no tty)" "Smoke test passed"
  fi
  chk "l0_core synthesizes on $PDK_DIGITAL (screen.sh)" "$ROOT/core/l0/librelane/screen.sh" "$S/screen"
  cd "$ROOT"

  if [ "$GUI" = 1 ] && [ "$PDK_FAMILY" = sky130 ]; then
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
      cd "$ROOT"
    else bad "no X display for --gui"; fi
  fi

  echo "== TOOLS.md names real paths"
  local miss=0 f
  for f in $(grep -oE '`\$EDA/[^` ]+`' "$ROOT/TOOLS.md" | tr -d '`' | grep -v '[*<]' | grep -v '\$PDK'); do
    [ -e "${f/\$EDA/$EDA}" ] || { echo "        missing: $f"; miss=1; }
  done
  [ $miss = 0 ] && ok "every \$EDA path in TOOLS.md exists" || bad "TOOLS.md names missing paths"

  echo "== repo l0 rtl commands from the docs"
  cd "$ROOT/core/l0"
  local L="src/shared.sv src/signext.sv src/alu.sv src/decoder.sv src/regfile.sv src/csrfile.sv src/memory.sv src/control.sv src/l0.sv"
  local LC="src/shared.sv src/signext.sv src/alu.sv src/decoder.sv src/regfile.sv src/csrfile.sv src/control.sv"
  chk "verilator lint l0 (control, with its memories)" verilator --lint-only -Wall -Wno-fatal $L --top-module control
  # yosys' own SystemVerilog reader drops `import isa_shared::*` and gives wrong counts: the slang front end is needed
  chk "yosys with slang synthesizes l0_core" yosys -q -p "plugin -i slang; read_slang --top l0_core $LC; synth -top l0_core"
  chk "l0_core has the memory ports (imem_*, dmem_*)" bash -c "awk '/^module l0_core/,/\\);/' src/control.sv | grep -cE '^ *(input|output) ' | grep -qx 12"
  cd "$ROOT"

  echo
  echo "pass=$pass fail=$fail  scratch=$S"
  [ "$fail" = 0 ]
}

# ==== shell and menu ===============================================================================================
cmd_shell() { echo "tools on PATH (EDA=$EDA). exit to leave."; exec "${SHELL:-bash}" -i; }

menu() {
  local a
  echo "tools: $EDA"
  echo "  1) install   set up what is missing"
  echo "  2) verify    check everything end to end (a few minutes)"
  echo "  3) shell     a new shell with the tools on PATH"
  echo "  4) view      open a layout (klayout, openroad, magic)"
  echo "  q) quit      (to put the tools on this shell: source eda.sh)"
  printf '> '; read -r a
  case $a in
    1) cmd_install ;;
    2) local g="" d; printf 'gui windows too? [y/N] '; read -r d; [ "$d" = y ] && g=--gui
       cmd_verify $g ;;
    3) cmd_shell ;;
    4) local t fl; printf 'klayout, openroad or magic: '; read -r t; printf 'file: '; read -r fl; cmd_view "$t" "$fl" ;;
    *) ;;
  esac
}

case "${1:-}" in
  "")      menu ;;
  install) shift; cmd_install "$@" ;;
  verify)  shift; cmd_verify "$@" ;;
  shell)   cmd_shell ;;
  view)    shift; cmd_view "$@" ;;
  *)       sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
