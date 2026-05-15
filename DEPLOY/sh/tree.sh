#!/usr/bin/env zsh
set -euo pipefail
setopt nullglob extendedglob

print_tree() {
  local dir="${1:-.}"
  dir="${dir%/}"

  for directory in "$dir"/**/*(/:t); do
    [[ "${directory##*/}" == .* ]] && continue
    local full_path="${dir}/${directory}"
    [[ -d "$full_path" ]] && print "${full_path}/"
  done

  for file in "$dir"/**/*(.N); do
    [[ "${file##*/}" == .* ]] && continue
    print "$file"
  done
}

print_tree "${1:-.}"
