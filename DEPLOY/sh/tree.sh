#!/bin/sh
set -eu

# DEPLOY/sh/tree.sh
#
# Thin portable wrapper around the constitution-aware tree generator.
# Provides the "full overview" requested during MASTER KISS/DRY redesign work.
# Works in both zsh and plain sh/linux environments.
#
# Usage:
#   ./tree.sh [--max-depth=3] [--summary]
#
# Created on demand per explicit user request for overview before
# implementing major architectural simplifications.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TOOLS_DIR="$SCRIPT_DIR/tools"
RUBY_TREE="$TOOLS_DIR/tree.rb"

ROOT="${1:-/root/pub4}"

if [ ! -f "$RUBY_TREE" ]; then
  echo "tree.rb not found at $RUBY_TREE" >&2
  exit 1
fi

# Prefer project ruby34 if present, else system ruby
if command -v ruby34 >/dev/null 2>&1; then
  RUBY=ruby34
elif command -v ruby >/dev/null 2>&1; then
  RUBY=ruby
else
  echo "No ruby interpreter found" >&2
  exit 1
fi

# Shift only if first arg was the root we consumed
if [ "$ROOT" != "/root/pub4" ] || [ "${2:-}" != "" ]; then
  shift || true
fi

exec "$RUBY" "$RUBY_TREE" "$ROOT" "$@"
