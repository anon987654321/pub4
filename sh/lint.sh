#!/usr/bin/env zsh
set -euo pipefail

setopt nullglob extendedglob
# Checks and fixes Ruby code files for errors.

# Usage: ./lint.sh

#
# Pure zsh: **/*.{rb,erb} glob instead of find

check_tool() {

  if ! command -v "$1" >/dev/null 2>&1; then

    echo "Error: $1 not found. Install it."
    exit 1

  fi

}

lint_ruby() {

  local file="$1"

  echo "Linting: $file"
  if ! reek "$file" >/dev/null 2>&1; then

    echo "Reek flagged: $file"

  fi
  if ! rubocop --autocorrect "$file" >/dev/null 2>&1; then

    echo "Rubocop failed: $file"

  fi

  echo "Done: $file"

}

check_tool "rubocop"
check_tool "reek"

# Use zsh glob pattern instead of find
for file in **/*.{rb,erb}(.N); do

  # Skip vendor and .gem directories
  if [[ "$file" == */.gem/* || "$file" == */vendor/* ]]; then

    continue

  fi

  lint_ruby "$file"

done

