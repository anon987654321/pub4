#!/usr/bin/env zsh
set -euo pipefail

setopt nullglob extendedglob

# Swaps out words in files or renames them.
# Usage: ./replace.sh [-f] <old> <new> [folder]

usage() {
  print -r -- "Usage: ./replace.sh [-f] <old> <new> [folder]"
}

die() {
  print -u2 -r -- "Error: $1"
  usage
  exit 1
}

rename_file() {
  typeset file=$1
  typeset new_file="${file//$old_str/$new_str}"
  [[ "$file" != "$new_file" && ! -e "$new_file" ]] || return 0

  if mv "$file" "$new_file" 2>/dev/null; then
    print -r -- "Renamed: $file -> $new_file"
    return 0
  fi

  print -r -- "Failed: $file"
}

replace_file() {
  typeset file=$1
  typeset file_type
  file_type=$(file -b "$file" 2>/dev/null) || return 0
  [[ "$file_type" == *text* ]] || return 0

  typeset content
  content=$(<"$file" 2>/dev/null) || return 0
  [[ "$content" == *"$old_str"* ]] || return 0

  typeset new_content="${content//$old_str/$new_str}"
  [[ "$content" != "$new_content" ]] || return 0

  cp "$file" "$file.bak" 2>/dev/null || print -r -- "Backup failed: $file"
  if print -rn -- "$new_content" > "$file" 2>/dev/null; then
    print -r -- "Updated: $file"
    rm -f "$file.bak"
    return 0
  fi

  print -r -- "Failed: $file"
  [[ -f "$file.bak" ]] && mv "$file.bak" "$file"
}

process_file() {
  if "$is_filename"; then
    rename_file "$1"
    return
  fi

  replace_file "$1"
}

is_filename=false

if [[ "${1:-}" == "-f" ]]; then
  is_filename=true
  shift
fi

old_str="${1:-}"
new_str="${2:-}"
folder="${3:-.}"

[[ -n "$old_str" && -n "$new_str" ]] || die "old and new strings required"
[[ -d "$folder" ]] || die "'$folder' is not a directory"

for file in "$folder"/**/*(.N); do
  process_file "$file"
done
