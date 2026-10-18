#!/bin/bash
# run.sh <tag> [json patch merged into config.json]    e.g.  run.sh t9 '{"CLOCK_PERIOD": 30}'
# the run is stored under $EDA/scratch (a run is about 1.8 GB) and linked as runs/<tag>, so every
# try is listed in runs/ next to this file. the config actually used is runs/<tag>/config.json.
# the PDK comes from .env (eda.sh): variant, slow corner and delay cells are filled in here, so nothing below names a PDK.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../../../eda.sh"
tag=$1; patch=${2:-{\}}
[ -e "$HERE/runs/$tag" ] && { echo "runs/$tag exists, pick a new tag"; exit 1; }
work=$EDA/scratch/l0-try${tag#t}   # tag t9 -> l0-try9, like tries 1 to 8
mkdir "$work"                       # fails if the tag was used before: nothing is overwritten
python3 - "$HERE/config.json" "$work/config.json" "$patch" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))
c['VERILOG_FILES']=[f.replace('dir::', sys.argv[1].rsplit('/',1)[0]+'/') for f in c['VERILOG_FILES']]
import os
slow=os.environ['PDK_SLOW']; sdc=sys.argv[1].rsplit('/',1)[0]+'/l0.sdc'
cells=[os.environ['STD_CELL_LIBRARY']+'__'+x for x in os.environ.get('PDK_DELAY_CELLS','').split(',') if x]
if cells: c['EXTRA_EXCLUDED_CELLS']=cells
c.update({'DEFAULT_CORNER':'nom_'+slow,'PNR_SDC_FILE':sdc,'SIGNOFF_SDC_FILE':sdc})
c.update(json.loads(sys.argv[3]))
json.dump(c,open(sys.argv[2],'w'),indent=2)
PY
mkdir -p "$HERE/runs"
ln -s "$work/runs/$tag" "$HERE/runs/$tag"
cd "$work"
librelane --pdk-root "$LIBRELANE_PDK_ROOT" --pdk "$PDK_DIGITAL" --run-tag "$tag" config.json > run.log 2>&1 && echo "done: $HERE/runs/$tag" || { echo "failed, see $work/run.log"; exit 1; }
