#!/usr/bin/env zsh
set -euo pipefail

setopt nullglob extendedglob
#

# OPENS MATCHING TEXT FILES IN VIM
#
# Usage: hack <string, leave empty to open all files>

#
# Pure zsh approach:
# - **/*(.N) glob qualifier for files only
# - [[ ]] pattern matching instead of grep
dir=${1:-"."}
# Only process text files using glob qualifier (.N = files, nullglob)
for file in **/*(.N); do
  # Search pattern using zsh pattern matching

  if [[ -z "$1" ]] || [[ $(<"$file") == *"$1"* ]]; then

    vim "$file"
  fi
done
