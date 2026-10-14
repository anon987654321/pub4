#!/bin/ksh
# Unprivileged manual entrypoint; the root cron runner is a separate installed file.
set -eu

case ${1:-} in
  -h|--help)
    echo "usage: ksh OPENBSD/bin/resource_guard.sh — request one load-guard tick through the installed runner"
    exit 0
    ;;
  "") ;;
  *) echo "resource_guard: no arbitrary arguments are accepted" >&2; exit 2 ;;
esac

if [ "$(id -u)" -eq 0 ]; then
  echo "resource_guard: refusing to execute checkout code as root; use the installed runner" >&2
  exit 2
fi

runner=/usr/local/bin/resource_guard.sh
[ -f "$runner" ] && [ -x "$runner" ] && [ ! -L "$runner" ] || {
  echo "resource_guard: trusted installed runner missing or symlinked; run reviewed OPERATOR.sh sync first" >&2
  exit 1
}
exec doas "$runner"
