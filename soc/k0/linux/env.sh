# sourced by the build scripts: finds helper tools and says what is missing before a long build starts.
#   tools installed without root go in $WORK/tools/bin (default ~/personal/k0-linux/tools/bin): they are
#   used after the system ones, so an installed bc wins. BC_PATH=<dir> puts a directory first instead.
WORK=${WORK:-$HOME/personal/k0-linux}
[ -d "$WORK/tools/bin" ] && PATH=$PATH:$WORK/tools/bin
[ -n "${BC_PATH:-}" ] && PATH=$BC_PATH:$PATH
export PATH

# need tool...: stop with a list when any is missing
need() {
  local missing=""
  for t in "$@"; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
  if [ -n "$missing" ]; then
    echo "missing host tools:$missing" >&2
    echo "install them, or build them into $WORK/tools/bin (or point BC_PATH= at their directory)" >&2
    exit 1
  fi
}
