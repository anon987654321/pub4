#!/usr/bin/env zsh
set -euo pipefail
# tree — pure zsh full-path listing, dirs then files
# Usage: tree [dir]   (defaults to current directory)
# No external commands. No ASCII art. No dotfiles.

setopt extended_glob null_glob

print_tree() {
  local dir="${${1:-.}%/}"
  local -a dirs files

  # Glob qualifiers:
  #   /   = directories only
  #   .   = regular files only
  #   on  = sort by name (natural order)
  # Dotfiles and dot-dirs are excluded by default (no D qualifier)
  dirs=(  "$dir"/**/*(/on)  )
  files=( "$dir"/**/*(.on)  )

  for d in $dirs;  { print "$d/" }
  for f in $files; { print "$f"  }
}

print_tree "${1:-.}"
