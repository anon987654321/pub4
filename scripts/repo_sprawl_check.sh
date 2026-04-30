#!/usr/bin/env bash
set -euo pipefail

# Simple warning-only sprawl checks.
# Exit code is always 0 unless command/runtime failures occur.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

max_depth="${1:-5}"

echo "[repo-sprawl] scanning tracked files with max depth=${max_depth}"

# depth is number of '/' separators in path
# e.g., a/b/c.txt => depth 2
violations="$(rg --files | awk -F/ -v max="$max_depth" 'NF-1 > max {print}')"

if [[ -n "$violations" ]]; then
  echo "[repo-sprawl] WARNING: files deeper than ${max_depth} levels:"
  echo "$violations" | sed -n '1,50p'
  total="$(echo "$violations" | wc -l | tr -d ' ')"
  if [[ "$total" -gt 50 ]]; then
    echo "[repo-sprawl] ... and $((total - 50)) more"
  fi
else
  echo "[repo-sprawl] OK: no files deeper than ${max_depth} levels"
fi

# Report top-level spread for quick visibility

echo "[repo-sprawl] top-level directory counts (tracked files):"
rg --files | awk -F/ '{print $1}' | sort | uniq -c | sort -nr | sed -n '1,20p'
