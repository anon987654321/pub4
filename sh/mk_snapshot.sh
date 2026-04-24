#!/usr/bin/env zsh
# Generate a focused MASTER snapshot for LLM review.
# Covers: lib/, exe/, data/, CLAUDE.md, Gemfile, key web files.
# Excludes: vendor/, web/vendor, tmp/, log/, test/, web/public, assets.
setopt extended_glob null_glob
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

ROOT=/home/dev/pub4/MASTER
OUT=$ROOT/snapshot.md
MAX=300

is_text() {
  case ${1:e} in
    rb|sh|yml|yaml|md|erb|ru|gemspec) return 0 ;;
  esac
  case ${1:t} in
    Gemfile|Rakefile|Dockerfile) return 0 ;;
  esac
  return 1
}

should_skip() {
  local f=$1
  # Skip vendor, tmp, log, test, assets, public, node_modules
  [[ $f == */vendor/* || $f == */tmp/* || $f == */log/* || $f == */test/* ]] && return 0
  [[ $f == */public/* || $f == */assets/* || $f == */node_modules/* ]] && return 0
  [[ $f == */spec/* || $f == */.git/* || $f == */storage/* ]] && return 0
  return 1
}

typeset -i n_files=0 n_lines=0 n_trunc=0

{
  print "# MASTER — Architecture Snapshot"
  print "# $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  print "# Ruby constitutional AI coding agent. OpenBSD VPS. ~6K LOC core."
  print

  # Ordered: CLAUDE.md first, then data/, then lib/, then exe/, then web app files
  local -a files=(
    $ROOT/CLAUDE.md(N)
    $ROOT/Gemfile(N)
    $ROOT/data/*.yml(N)
    $ROOT/lib/**/*.rb(N)
    $ROOT/exe/master(N)
    $ROOT/web/config/routes.rb(N)
    $ROOT/web/app/controllers/*.rb(N)
    $ROOT/web/config/application.rb(N)
  )

  for file in $files; do
    should_skip $file && continue
    is_text $file     || continue

    local rel=${file#$ROOT/}
    local -a body=( "${(f)$(<$file)}" )
    local -i n=${#body}

    print "## \`$rel\`"
    local ext=${file:e}
    [[ -z $ext ]] && ext=rb
    print '```'"$ext"
    if [[ $n -gt $MAX ]]; then
      print -l -- "${(@)body[1,$MAX]}"
      print "... $((n - MAX)) lines truncated ($n total)"
      (( n_trunc++ ))
    else
      print -l -- "${body[@]}"
    fi
    print '```'
    print

    (( n_files++ ))
    (( n_lines += n ))
  done

  printf '---\nfiles: %d | lines: %d | truncated: %d | est. tokens: ~%d\n' \
    $n_files $n_lines $n_trunc $(( n_lines * 6 / 5 ))

} > $OUT

printf 'saved: %s  (%d files, %d lines, ~%d tokens)\n' \
  $OUT $n_files $n_lines $(( n_lines * 6 / 5 ))
