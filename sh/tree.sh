#!/usr/bin/env zsh
# tree — full-path listing, dirs then files. No dotfiles. No external commands.
# Usage: tree [dir]
set -euo pipefail
setopt extended_glob null_glob

print_tree() {
  local dir="${${1:-.}%/}"
  local -a dirs=( "$dir"/**/*(/on) )
  local -a files=( "$dir"/**/*(.on) )
  for d in $dirs;  { print -- "$d/" }
  for f in $files; { print -- "$f"  }
}

print_tree "${1:-.}"
