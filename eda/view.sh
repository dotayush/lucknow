#!/bin/bash
# opens a LibreLane result in a viewer, with layer names (klayout) or the database loaded (openroad).
#   view.sh klayout <run>/final/gds/<design>.gds
#   view.sh openroad <run>/final/odb/<design>.odb [sdc]    # any step's .odb works too
#   view.sh magic <run>/final/mag/<design>.mag
# openroad -gui takes a Tcl script, not a database: give it an .odb on the command line and
# it tries to run the binary as Tcl (GUI-0070 "invalid command name"). so the db is read by a script.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
tool=$1; file=$(readlink -f "$2"); sdc=${3:-}
SKY=$PDK_ROOT/sky130A
case $tool in
  klayout)
    # KLAYOUT_PATH makes the PDK macros visible too (menu "Efabless sky130", D25 View = the 3D viewer)
    export KLAYOUT_PATH=$SKY/libs.tech/klayout
    # the nix klayout cannot reach the host graphics driver by itself; the 3D viewer needs OpenGL (see nixrun.sh)
    export NIXRUN_GL=1
    exec klayout -l $SKY/libs.tech/klayout/tech/sky130A.lyp "$file" ;;
  openroad)
    dir=$(dirname "$file"); name=$(basename "$file" .odb)
    tcl=$(mktemp "${TMPDIR:-/tmp}/view-XXXXXX.tcl")
    {
      echo "read_db $file"
      for l in $SKY/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib; do echo "read_liberty $l"; done
      [ -n "$sdc" ] && echo "read_sdc [file normalize $sdc]"
    } > "$tcl"
    exec openroad -gui "$tcl" ;;
  magic)
    exec magic -d 24BIT -rcfile $SKY/libs.tech/magic/sky130A.magicrc "$file" ;;
  *) echo "usage: $0 klayout|openroad|magic <file> [sdc]"; exit 1 ;;
esac
