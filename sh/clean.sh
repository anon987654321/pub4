#!/usr/bin/env zsh
set -euo pipefail

# Removes carriage returns, trailing whitespaces, and extra blank lines from text files.
# Usage: ./clean.sh [target_folder]

dir="${1:-.}"
if [[ ! -d "$dir" ]]; then

  print "Error: '$dir' is not a directory"

  exit 1

fi

for file in "$dir"/**/*(.N); do
  # Check if file is text using pure zsh pattern matching

  local filetype=$(file -b "$file")

  if [[ $filetype == *text* ]]; then

    tmp=$(mktemp)

    if [[ $? -ne 0 ]]; then

      print "Error: mktemp failed"

      exit 1

    fi

    # Pure zsh: remove CRLF, trim trailing whitespace, reduce blank lines
    local content=$(<"$file")

    content=${content//$'\r'/}  # Remove carriage returns

    local -a lines=("${(@f)content}")  # Split into array of lines
    local -a cleaned=()

    local prev_blank=0

    for line in "${lines[@]}"; do
      # Trim trailing whitespace

      line=${line%%[[:space:]]#}

      if [[ -z $line ]]; then
        # Blank line - only add if previous wasn't blank

        if [[ $prev_blank -eq 0 ]]; then

          cleaned+=("")

          prev_blank=1

        fi

      else

        cleaned+=("$line")

        prev_blank=0

      fi

    done

    # Write cleaned content
    print -l "${cleaned[@]}" > "$tmp"

    if [[ $? -eq 0 ]]; then
      mv "$tmp" "$file"

      print "Cleaned: $file"

    else

      rm "$tmp"

      print "Failed: $file"

    fi

  fi

done

