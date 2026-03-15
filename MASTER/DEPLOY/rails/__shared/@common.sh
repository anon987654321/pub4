#!/usr/bin/env zsh
set -euo pipefail

# Common helpers for DEPLOY/rails installers.
# This file is intended to be sourced by app installer scripts.

SCRIPT_DIR="${0:a:h}"

log() {
  print -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

warn() {
  print -u2 -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*"
}

err() {
  print -u2 -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*"
}

source_optional_feature_modules() {
  local feature_file
  local -a patterns=(
    "${SCRIPT_DIR}/@*_features.sh"
    "${SCRIPT_DIR}/@stimulus_controllers/*.sh"
  )

  setopt local_options null_glob
  for feature_file in ${~^patterns}; do
    if ! source "$feature_file"; then
      warn "Failed to source feature module: $feature_file"
    else
      log "Loaded feature module: $feature_file"
    fi
  done
}

# Usage: get_app_port "brgen"
get_app_port() {
  local app_name="$1"
  local master_json="${MASTER_JSON:-${SCRIPT_DIR}/../master.json}"
  local port

  [[ -n "$app_name" ]] || {
    err "Application name is required"
    return 1
  }

  [[ -f "$master_json" ]] || {
    err "master.json not found at $master_json"
    return 1
  }

  command -v jq >/dev/null 2>&1 || {
    err "jq is required to parse master.json"
    return 1
  }

  port="$(jq -r --arg app_name "$app_name" '.apps[] | select(.name == $app_name) | .port // empty' "$master_json")"
  [[ -n "$port" ]] || {
    err "No port configured for app '$app_name' in $master_json"
    return 1
  }

  print -r -- "$port"
}

source_optional_feature_modules
