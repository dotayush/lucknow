#!/usr/bin/env bash
# an interactive shell on the core: your terminal is the uart. boots in about a minute, then type.
# Ctrl-] quits. needs sim/build.sh, and buildroot/build.sh + busybox.sh for the busybox image (default),
# or IMAGE=Image for the small built-in shell.
#   ./linux/shell.sh
#   IMAGE=Image ./linux/shell.sh
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/out}
exec $HERE/../sim/obj/Vsoc +image=$OUT/${IMAGE:-Image.busybox} +image=$OUT/k0.dtb@807f0000 +interactive "$@"
