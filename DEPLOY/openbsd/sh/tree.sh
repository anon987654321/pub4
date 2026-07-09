#!/bin/sh
set -eu

# DEPLOY/openbsd/sh/tree.sh
#
# Thin portable wrapper around the constitution-aware tree generator.
# Provides the "full overview" requested during MASTER KISS/DRY redesign work.
# Works in both zsh and plain sh/linux environments.
#
# Usage:
#   ./tree.sh [--max-depth=4] [--summary]
#   ./tree.sh /some/other/root --max-depth=3
#
# Created on demand per explicit user request for overview before
# implementing major architectural simplifications.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RUBY_TREE="$SCRIPT_DIR/../tools/tree.rb"

ROOT="${PUB4_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)}"

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
