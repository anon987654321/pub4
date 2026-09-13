#!/bin/sh
set -eu

# OPENBSD/tree.sh — portable sh wrapper around tools/tree.rb.
#
# Usage:
#   ./tree.sh [root] [--max-depth=4] [--summary] [--pub4-overview]
#   ./tree.sh --help      # every mode tools/tree.rb takes

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RUBY_TREE="$SCRIPT_DIR/tools/tree.rb"

ROOT="${PUB4_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}"

# If the first argument looks like a directory (or .), treat it as root
if [ $# -gt 0 ]; then
  case "$1" in
    --*|-*) ;;
    *)
      if [ -d "$1" ] 2>/dev/null || [ "$1" = "." ]; then
        ROOT="$1"
        shift
      fi
      ;;
  esac
fi

if [ ! -f "$RUBY_TREE" ]; then
  echo "tree.rb not found at $RUBY_TREE" >&2
  exit 1
fi

if command -v ruby34 >/dev/null 2>&1; then
  RUBY=ruby34
else
  RUBY=ruby
fi

exec "$RUBY" "$RUBY_TREE" "$ROOT" "$@"
