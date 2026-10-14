#!/bin/ksh
# Root-owned, fixed-target preparation for one Rails app's CI run.
# This file is installed from OPENBSD/usr/local/libexec by OPERATOR.sh.
set -eu
PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

app=\${1:-}
case "$app" in
  brgen|amber|bsdports) ;;
  *) echo "ci-prepare: refused unknown app: $app" >&2; exit 64 ;;
esac

[ "$(id -u)" -eq 0 ] || { echo "ci-prepare: must run as root through pub4-admin" >&2; exit 77; }

if ! grep -q '^_pub4ci:' /etc/group; then
  /usr/sbin/groupadd _pub4ci
fi
/usr/sbin/usermod -G _pub4ci "$app"

[ -d /home/dev ] && [ ! -L /home/dev ] || {
  echo "ci-prepare: /home/dev is not a real directory" >&2
  exit 1
}
/bin/chgrp _pub4ci /home/dev
/bin/chmod 750 /home/dev

storage="/home/$app/app/storage"
if [ -L "$storage" ]; then
  echo "ci-prepare: refusing storage symlink: $storage" >&2
  exit 1
fi
if [ -d "$storage" ]; then
  /bin/chmod 750 "$storage"
fi
