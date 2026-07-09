#!/usr/bin/env sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if command -v ruby34 >/dev/null 2>&1; then
  exec ruby34 "$ROOT/RAILS/port_inventory_gate.rb"
fi

exec ruby "$ROOT/RAILS/port_inventory_gate.rb"
