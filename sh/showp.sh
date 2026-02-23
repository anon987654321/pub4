#!/usr/bin/env zsh
# showp — dump every text file as fenced Markdown. Output: OUT.MD (or $1).
# Usage: showp [output_file]
set -euo pipefail
setopt null_glob extended_glob

main() {
  local out="${1:-OUT.MD}"

  {
    for file in **/*(-.N); do
      [[ "$file" == "$out" ]] && continue
      [[ $(file -b "$file" 2>/dev/null) == *text* ]] || continue
      print -- "## \`${file#./}\`"
      print -- '```'
      print -r -- "$(<"$file")"
      print -- '```'
      print
    done
  } > "$out"

  print -- "saved: $out"
}

main "$@"
