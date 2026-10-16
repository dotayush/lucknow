#!/bin/bash
# run a command with the librelane toolchain (openroad, yosys, magic, netgen, klayout, librelane)
# from the nix store copied out of the librelane image. no root: bwrap mounts the store at /nix/store.
# usage: nixrun.sh openroad -version
EDA=${EDA:-/media/ayush/secondary/eda}
STORE=$EDA/nixroot/store
[ -d "$STORE" ] || { echo "nixrun: $STORE missing" >&2; exit 1; }
args=(--unshare-user --die-with-parent --tmpfs /)
for d in /usr /bin /sbin /lib /lib64 /etc /opt /var /run /home /media /mnt /srv; do
  [ -e "$d" ] && args+=(--bind "$d" "$d")
done
args+=(--unsetenv LD_LIBRARY_PATH --unsetenv LD_PRELOAD --bind "$STORE" /nix/store --dev-bind /dev /dev --proc /proc --bind /sys /sys --bind /tmp /tmp)
# image env: PATH with every tool, python path, certs. HOME stays yours.
while IFS= read -r l; do
  case $l in PATH=*) args+=(--setenv PATH "${l#PATH=}:/usr/bin:/bin");; esac
  case $l in NIX_PYTHONPATH=*|LANG=*|LC_ALL=*|LC_CTYPE=*) args+=(--setenv "${l%%=*}" "${l#*=}");; esac
done < "$EDA/nixroot/image.env"
exec bwrap "${args[@]}" "$@"
