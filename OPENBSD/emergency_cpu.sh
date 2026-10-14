#!/bin/ksh
# Unprivileged entrypoint. The fixed root-owned implementation is installed at /usr/local/bin.
set -eu

case ${1:-} in
  -h|--help)
    echo "usage: ksh OPENBSD/emergency_cpu.sh — request the fixed installed emergency recovery"
    exit 0
    ;;
  "") ;;
  *) echo "emergency_cpu: no arbitrary arguments are accepted" >&2; exit 2 ;;
esac

if [ "$(id -u)" -eq 0 ]; then
  echo "emergency_cpu: refusing to execute checkout code as root; use the installed runner" >&2
  exit 2
fi

runner=/usr/local/bin/emergency_cpu.sh
[ -f "$runner" ] && [ -x "$runner" ] && [ ! -L "$runner" ] || {
  echo "emergency_cpu: trusted installed runner missing or symlinked; run reviewed OPERATOR.sh sync first" >&2
  exit 1
}
exec doas "$runner"
