#!/bin/ksh
# CC01–CC02: OpenBSD sysupgrade + syspatch + pkg_add -u + sysmerge
# Run on VPS during maintenance window. Idempotent checks before destructive steps.

set -e

echo "== CC01 sysupgrade (7.8 -> 7.9) =="
if uname -r | grep -q 'OpenBSD 7\.9'; then
  echo "OK: already on OpenBSD 7.9"
else
  echo "Run: doas sysupgrade -r"
  echo "Reboot, then re-run this script."
  exit 0
fi

echo "== CC02 syspatch =="
doas syspatch

echo "== CC02 pkg_add -u =="
doas pkg_add -u

echo "== CC02 sysmerge =="
doas sysmerge -d

echo "OK: upgrade hygiene complete — verify services with DEPLOY/health_check.rb"