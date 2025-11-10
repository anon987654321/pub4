#!/usr/bin/env zsh
set -euo pipefail

# Creates a Markdown list of text files and their contents.
# Usage: ./showp.sh

#
# Pure zsh: ${PWD##*/} instead of basename

root="${PWD##*/}"

date=$(date +"%Y-%m-%d_%H%M%S")

output="$HOME/OUTPUT_${root}_${date}.md"
{

  for file in **/*(-.N); do

    if [[ "$file" == "$output" ]]; then
      continue

    fi

    # Pure zsh: pattern matching instead of grep

    local file_type=$(file -b "$file" 2>/dev/null)

    if [[ "$file_type" == *text* ]]; then
      echo "## \`${file#./}\`"

      echo '```'

      cat "$file" 2>/dev/null || echo "Read failed: $file"

      echo '```'

      echo

    fi

  done

} > "$output" 2>>"$HOME/script_errors.log"

if [[ $? -ne 0 ]]; then

  echo "Failed to write $output; see $HOME/script_errors.log"

  exit 1

fi

echo "Saved: $output"

