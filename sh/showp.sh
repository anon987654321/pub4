#!/usr/bin/env zsh
# showp — dump project source files as fenced Markdown for LLM context.
# Usage: showp [output_file] [max_lines_per_file]
setopt extended_glob null_glob

is_text() {
  case ${1:e} in
    rb|py|js|ts|zsh|sh|bash|md|yml|yaml|json|toml|gemspec|txt|erb|conf|ini|env) return 0 ;;
  esac
  case ${1:t} in
    Gemfile|Rakefile|Makefile|Dockerfile) return 0 ;;
  esac
  return 1
}

in_skip_dir() {
  local seg
  for seg in ${(s:/:)1}; do
    case $seg in
      .git|vendor|tmp|var|node_modules|.bundle|coverage|log|dist) return 0 ;;
    esac
  done
  return 1
}

main() {
  local out="${1:-OUT.MD}"
  local -i max="${2:-400}" n_files=0 n_lines=0 n_trunc=0

  {
    print "# Project Snapshot — $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    print

    for file in **/*(-.); do
      [[ $file == $out ]] && continue
      in_skip_dir $file        && continue
      is_text $file            || continue

      local -a body=( "${(f)$(<$file)}" )
      local -i n=${#body}

      print "## \`$file\`"
      print '```'"${file:e}"
      if [[ $n -gt $max ]]; then
        print -l -- "${(@)body[1,$max]}"
        print "… $((n - max)) lines truncated ($n total)"
        n_trunc=$(( n_trunc + 1 ))
      else
        print -l -- "${body[@]}"
      fi
      print '```'
      print

      n_files=$(( n_files + 1 ))
      n_lines=$(( n_lines + n ))
    done

    printf 'files: %d · lines: %d · truncated: %d · est. tokens: ~%d\n' \
      $n_files $n_lines $n_trunc $(( n_lines * 6 / 5 ))
  } > "$out"

  printf 'saved: %s  (%d files, %d lines, ~%d tokens)\n' \
    "$out" $n_files $n_lines $(( n_lines * 6 / 5 ))
}

main "$@"
