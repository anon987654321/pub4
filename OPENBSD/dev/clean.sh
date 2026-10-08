#!/usr/bin/env zsh
set -euo pipefail
setopt nullglob extendedglob

dir="${1:-.}"

[[ -d "$dir" ]] || { print "Error: '$dir' is not a directory"; exit 1 }

for file in "$dir"/**/*(.N); do
  local filetype=$(file -b "$file")
  [[ $filetype == *text* ]] || continue

  local content=$(<"$file")
  content=${content//$''/}
  local -a lines=("${(@f)content}")
  local -a cleaned=()
  local prev_blank=0

  for line in "${lines[@]}"; do
    line=${line%%[[:space:]]#}
    if [[ -z $line ]]; then
      if [[ $prev_blank -eq 0 ]]; then
        cleaned+=("")
        prev_blank=1
      fi
    else
      cleaned+=("$line")
      prev_blank=0
    fi
  done

  local tmp=$(mktemp)
  print -l "${cleaned[@]}" > "$tmp" && mv "$tmp" "$file" && print "Cleaned: $file" || { rm "$tmp"; print "Failed: $file" }
done
