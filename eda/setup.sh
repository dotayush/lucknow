#!/usr/bin/env bash
# open silicon flow for lucknow: librelane (yosys, openroad, magic, netgen, klayout in a container)
# + the sky130 pdk. everything but the container image lives under $EDA.
set -euo pipefail

EDA=${EDA:-/media/ayush/secondary/eda}
PDK_ROOT=${PDK_ROOT:-$EDA/pdk}
VENV=$EDA/venv

mountpoint -q "$(df --output=target "$EDA" | tail -1)" || { echo "$EDA is not mounted"; exit 1; }
command -v bwrap >/dev/null || { echo "bwrap not found"; exit 1; }

mkdir -p "$EDA"/{pdk,src,tools/bin}

# the nix store with openroad, klayout, yosys, magic, netgen, librelane lives in $EDA/nixroot (copied once out of
# the librelane 3.0.16 docker image). nixrun runs a tool against it; the wrappers are for the names below.
install -m755 "$(dirname "$0")/nixrun.sh" "$EDA/tools/bin/nixrun"
for t in openroad klayout sta librelane; do
  printf '#!/bin/bash\nexec %s/tools/bin/nixrun %s "$@"\n' "$EDA" "$t" > "$EDA/tools/bin/$t"; chmod +x "$EDA/tools/bin/$t"
done

# bash for make, see make.shim
install -m755 "$(dirname "$0")/make.shim" "$EDA/tools/bin/make"

# librelane + ciel (the pdk downloader) in one venv
[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet librelane klayout

# the sky130 pdk is fetched into $PDK_ROOT by librelane's first run (the smoke test below)

cat <<MSG
installed under $EDA
  source $(dirname "$0")/env.sh
  librelane --pdk-root \$LIBRELANE_PDK_ROOT --smoke-test
MSG
