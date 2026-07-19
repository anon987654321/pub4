#!/usr/bin/env bash
# Thin wrapper — agent logic lives in dilla.rb (learn-playlist-agent).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec ruby "$ROOT/dilla.rb" learn-playlist-agent "$@"
