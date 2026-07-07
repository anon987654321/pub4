#!/usr/bin/env sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if command -v ruby34 >/dev/null 2>&1; then
  exec ruby34 "$ROOT/DEPLOY/rails/port_inventory_gate.rb"
fi

exec ruby "$ROOT/DEPLOY/rails/port_inventory_gate.rb"
