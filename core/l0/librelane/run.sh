#!/bin/bash
# run.sh <tag> [json patch merged into config.json]    e.g.  run.sh t9 '{"CLOCK_PERIOD": 30}'
# the run is stored on the external SSD (a run is about 1.8 GB) and linked as runs/<tag>, so every
# try is listed in runs/ next to this file. the config actually used is runs/<tag>/resolved.json.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../../../eda/env.sh"
tag=$1; patch=${2:-{\}}
[ -e "$HERE/runs/$tag" ] && { echo "runs/$tag exists, pick a new tag"; exit 1; }
work=$EDA/scratch/l0-try${tag#t}   # tag t9 -> l0-try9, like tries 1 to 8
mkdir "$work"                       # fails if the tag was used before: nothing is overwritten
python3 - "$HERE/config.json" "$work/config.json" "$patch" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))
c['VERILOG_FILES']=[f.replace('dir::', sys.argv[1].rsplit('/',1)[0]+'/') for f in c['VERILOG_FILES']]
c.update(json.loads(sys.argv[3]))
json.dump(c,open(sys.argv[2],'w'),indent=2)
PY
mkdir -p "$HERE/runs"
ln -s "$work/runs/$tag" "$HERE/runs/$tag"
cd "$work"
librelane --pdk-root "$LIBRELANE_PDK_ROOT" --pdk sky130A --run-tag "$tag" config.json > run.log 2>&1 && echo "done: $HERE/runs/$tag" || { echo "failed, see $work/run.log"; exit 1; }
