#!/bin/sh
# Snapshot /var/run/dmesg.boot into OPENBSD/dmesg/ (idempotent per day).

set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
BOOT=/var/run/dmesg.boot
HOST=$(hostname -s 2>/dev/null || hostname)
STAMP=$(date +%Y%m%d)
DEST="${ROOT}/${HOST}.${STAMP}"

if [ ! -r "$BOOT" ]; then
  echo "capture_dmesg: ${BOOT} unreadable" >&2
  exit 1
fi

cp "$BOOT" "$DEST"
echo "capture_dmesg: wrote ${DEST}"