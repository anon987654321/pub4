#!/usr/bin/env zsh
set -euo pipefail

# Helpers for DEPLOY/rails installers.
SCRIPT_DIR="${0:a:h}"

log()   { printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }
warn()  { printf '[%s] WARN: %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }
err()   { printf '[%s] ERROR: %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }

load_feature_modules() {
  local feature
  local -a patterns=(
    "${SCRIPT_DIR}"/*_features.sh
    "${SCRIPT_DIR}"/*/stimulus_controllers/*.sh
  )
  setopt null_glob
  for feature in ${patterns[@]}; do
    if ! source "$feature"; then
      warn "Failed to source $feature"
    else
      log "Loaded $feature"
    fi
  done
}

get_app_port() {
  local app_name=${1:-}
  [[ -n $app_name ]] || { err "Application name required"; return 1; }

  local master_json=${MASTER_JSON:-"$SCRIPT_DIR/../master.json"}
  [[ -f $master_json ]] || { err "master.json not found at $master_json"; return 1; }
  command -v jq >/dev/null || { err "jq not installed"; return 1; }

  local port
  port=$(jq -r --arg app_name "$app_name" '.apps[] | select(.name == $app_name) | .port // empty' "$master_json")
  [[ -n $port ]] || { err "No port for $app_name in $master_json"; return 1; }
  printf '%s\n' "$port"
}

load_feature_modules