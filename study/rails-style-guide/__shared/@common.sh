#!/usr/bin/env zsh
# __shared/@common.sh — common Rails 8 installer helpers
# Source from app installers. Do not execute directly.
set -euo pipefail

SCRIPT_DIR=${0:a:h}

log()  { print -P "%F{cyan}[%D{%H:%M:%S}]%f $*"; }
warn() { print -P "%F{yellow}WARN%f $*" >&2; }
err()  { print -P "%F{red}ERR%f $*" >&2; }

# Idempotent model generation: skip if model file exists
gen_model() {
  local name=$1; shift
  local path="app/models/${name:l}.rb"
  if [[ -f $path ]]; then
    log_ok "model $name already exists"
    return 0
  fi
  bin/rails generate model "$name" "$@" --no-test-framework
  bin/rails db:migrate
}

# Idempotent scaffold generation
gen_scaffold() {
  local name=$1; shift
  local path="app/models/${name:l}.rb"
  if [[ -f $path ]]; then
    log_ok "scaffold $name already exists"
    return 0
  fi
  bin/rails generate scaffold "$name" "$@" --no-test-framework
  bin/rails db:migrate
}

# Write file only if it does not exist
write_once() {
  local path=$1
  [[ -f $path ]] && { log_ok "$path exists"; return 0; }
  mkdir -p "${path:h}"
  cat > "$path"
  log_ok "wrote $path"
}

# Overwrite file unconditionally
write_file() {
  local path=$1
  mkdir -p "${path:h}"
  cat > "$path"
  log_ok "wrote $path"
}
