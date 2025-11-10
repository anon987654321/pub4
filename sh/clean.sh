#!/usr/bin/env zsh
set -euo pipefail

# Removes carriage returns, trailing whitespaces, and extra blank lines from text files.
# Usage: ./clean.sh [target_folder]

dir="${1:-.}"
if [ ! -d "$dir" ]; then

  printf "Error: '%s' is not a directory\n" "$dir"
  exit 1
fi

for file in "$dir"/**/*(.N); do

  if file -b "$file" | grep -q "text"; then

    tmp=$(mktemp)
    if [[ $? -ne 0 ]]; then

      echo "Error: mktemp failed"
      exit 1

    fi

    # Removes CRLF, trims trailing whitespaces, reduces blank lines.

    tr -d '\r' < "$file" | awk '{sub(/[ \t]+$/, "");} NF{print; if(p)print ""} {p=NF}' > "$tmp" 2>/dev/null

    if [[ $? -eq 0 ]]; then
      mv "$tmp" "$file"

      echo "Cleaned: $file"

    else

      rm "$tmp"

      echo "Failed: $file"

    fi

  fi

done

