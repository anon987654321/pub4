#!/usr/bin/env zsh
set -euo pipefail

setopt nullglob extendedglob
#

# SIMPLE FULL-PATH LISTING FOR FILES AND FOLDERS
#
# Usage: tree <folder, leave empty to use current folder>

#
# Modern zsh approach: Uses glob qualifiers instead of external commands
# - **/*(.N) = files only, N = nullglob (no error if empty)
# - **/*(/) = directories only
# - ${file#$dir/} = strip directory prefix (pure parameter expansion)
print_tree() {
  local dir="${1:-.}"
  # Remove trailing slash if present
  dir="${dir%/}"

  # Print directories first (with trailing slash)
  for directory in "$dir"/**/*(/:t); do

    # Skip dotfiles and dotfolders
    [[ "${directory##*/}" == .* ]] && continue

    # Reconstruct full path and print with trailing slash
    local full_path="${dir}/${directory}"
    [[ -d "$full_path" ]] && print "${full_path}/"
  done

  # Print all files (no trailing slash)
  for file in "$dir"/**/*(.N); do
    # Skip dotfiles
    [[ "${file##*/}" == .* ]] && continue

    print "$file"
  done
}
print_tree "${1:-.}"

