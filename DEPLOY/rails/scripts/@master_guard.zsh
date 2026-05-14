#!/bin/zsh
# @master_guard.zsh
# Shared helpers for Rails generators that must pass MASTER scan/sweep
# before generated files are allowed to be installed.

set -euo pipefail

: "${PUB4_ROOT:=${PUB4_ROOT:-$(pwd)}}"
: "${MASTER_DIR:=${MASTER_DIR:-${PUB4_ROOT}/MASTER}}"
: "${MASTER_REQUIRED:=1}"

log() { print -P "%F{cyan}==>%f $*"; }
warn() { print -P "%F{yellow}WARN%f $*" >&2; }
err() { print -P "%F{red}ERR%f $*" >&2; }

master_available() {
  [[ -d "$MASTER_DIR" && -f "$MASTER_DIR/exe/master" ]]
}

master_scan_file() {
  local path=$1

  if ! master_available; then
    if [[ "$MASTER_REQUIRED" == "1" ]]; then
      err "MASTER is required but not available at $MASTER_DIR"
      return 1
    fi
    warn "MASTER unavailable; allowing $path because MASTER_REQUIRED=0"
    return 0
  fi

  (
    cd "$MASTER_DIR"
    bundle exec ruby exe/master "scan ${path}" >/tmp/master_scan.$$ 2>&1 || {
      cat /tmp/master_scan.$$ >&2
      rm -f /tmp/master_scan.$$
      return 1
    }
    rm -f /tmp/master_scan.$$
  )
}

master_sweep_path() {
  local path=$1

  if ! master_available; then
    if [[ "$MASTER_REQUIRED" == "1" ]]; then
      err "MASTER is required but not available at $MASTER_DIR"
      return 1
    fi
    warn "MASTER unavailable; allowing sweep for $path because MASTER_REQUIRED=0"
    return 0
  fi

  (
    cd "$MASTER_DIR"
    bundle exec ruby exe/master "sweep ${path}" >/tmp/master_sweep.$$ 2>&1 || {
      cat /tmp/master_sweep.$$ >&2
      rm -f /tmp/master_sweep.$$
      return 1
    }
    rm -f /tmp/master_sweep.$$
  )
}

guarded_write() {
  local path=$1
  local tmp_dir=".master/generated"
  local tmp_path="${tmp_dir}/${path//\//__}"

  mkdir -p "$tmp_dir" "${path:h}"
  cat > "$tmp_path"

  log "MASTER scan: $path"
  master_scan_file "$tmp_path"

  cp "$tmp_path" "$path"
  log "installed: $path"
}

guarded_sweep_generated() {
  local path=${1:-.}
  log "MASTER sweep: $path"
  master_sweep_path "$path"
}
