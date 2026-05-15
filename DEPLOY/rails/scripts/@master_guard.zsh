#!/bin/zsh
# @master_guard.zsh
# Shared helpers for generators that must pass MASTER scan/sweep
# before generated files are allowed to be installed.

set -euo pipefail

: "${pub4_root:=$(pwd)}"
: "${master_dir:=$pub4_root/MASTER}"
: "${master_required:=1}"

log() { print -P "%F{cyan}==>%f $*"; }
warn() { print -P "%F{yellow}WARN%f $*" >&2; }
err() { print -P "%F{red}ERR%f $*" >&2; }

indent_output() {
  local line
  while IFS= read -r line; do
    print "    $line"
  done
}

master_available() {
  [[ -d "$master_dir" && -f "$master_dir/exe/master" ]]
}

master_command() {
  local command=$1
  local path=$2
  local output

  if ! master_available; then
    if [[ "$master_required" == "1" ]]; then
      err "MASTER required but not found at $master_dir"
      return 1
    fi

    warn "MASTER unavailable; allowing $command for $path because master_required=0"
    return 0
  fi

  log "MASTER $command: $path"

  if ! output=$(cd "$master_dir" && bundle exec ruby exe/master "$command $path" 2>&1); then
    err "MASTER $command failed for $path"
    print -r -- "$output" | indent_output
    return 1
  fi

  if [[ -n "$output" ]]; then
    warn "MASTER $command output for $path"
    print -r -- "$output" | indent_output
  fi
}

master_scan_file() {
  master_command scan "$1"
}

master_sweep_path() {
  master_command sweep "$1"
}

guarded_write() {
  local path=$1
  local tmp_dir=".master/generated"
  local tmp_path="$tmp_dir/${path//\//__}"

  mkdir -p "$tmp_dir" "${path:h}"
  cat > "$tmp_path"

  master_scan_file "$tmp_path"
  cp "$tmp_path" "$path"
  log "installed: $path"
}

guarded_sweep_generated() {
  local path=${1:-.}
  master_sweep_path "$path"
}

rails_bin() {
  print rails34
}

run_if_missing() {
  local target=$1
  shift

  if [[ -e "$target" ]]; then
    log "skip existing: $target"
    return 0
  fi

  "$@"
}
