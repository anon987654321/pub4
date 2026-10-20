#!/bin/ksh
# Root-owned, fixed-target preparation for one Rails app's CI run.
# This file is installed from OPENBSD/usr/local/libexec by OPERATOR.sh.
set -eu
PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

app=${1:-}
case "$app" in
  brgen|bsdports) ;;
  *) echo "ci-prepare: refused unknown app: $app" >&2; exit 64 ;;
esac

[ "$(id -u)" -eq 0 ] || { echo "ci-prepare: must run as root through pub4-admin" >&2; exit 77; }

# Do not let an allowlisted app name turn a symlinked home/app path into a
# privileged chmod target. Verify each ancestor and its ownership before touching
# storage or the shared checkout permissions.
app_uid=$(/usr/bin/id -u "$app")
app_home="/home/$app"
app_dir="$app_home/app"
[ -d "$app_home" ] && [ ! -L "$app_home" ] &&
  [ "$(stat -f %u "$app_home")" = "$app_uid" ] || {
  echo "ci-prepare: app home must be a real directory owned by $app" >&2
  exit 1
}
[ -d "$app_dir" ] && [ ! -L "$app_dir" ] &&
  [ "$(stat -f %u "$app_dir")" = "$app_uid" ] || {
  echo "ci-prepare: app directory must be a real directory owned by $app" >&2
  exit 1
}

[ -d /home/dev ] && [ ! -L /home/dev ] || {
  echo "ci-prepare: /home/dev is not a real directory" >&2
  exit 1
}
storage="$app_dir/storage"
if [ -e "$storage" ] || [ -L "$storage" ]; then
  [ -d "$storage" ] && [ ! -L "$storage" ] &&
    [ "$(stat -f %u "$storage")" = "$app_uid" ] || {
      echo "ci-prepare: storage must be a real app-owned directory: $storage" >&2
      exit 1
    }
fi

if ! grep -q '^_pub4ci:' /etc/group; then
  /usr/sbin/groupadd _pub4ci
fi
/usr/sbin/usermod -G _pub4ci "$app"

/bin/chgrp _pub4ci /home/dev
/bin/chmod 750 /home/dev
if [ -d "$storage" ]; then
  /bin/chmod 750 "$storage"
fi
