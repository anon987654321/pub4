#!/usr/bin/env sh
set -eu
set -o pipefail

# Helpers for DEPLOY/rails installers.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

log()   { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn()  { printf '[%s] WARN: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
err()   { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

load_feature_modules() {
  for pattern in "$SCRIPT_DIR"/*_features.sh "$SCRIPT_DIR"/*/stimulus_controllers/*.sh; do
    for feature in $pattern; do
      [ -f "$feature" ] && [ -r "$feature" ] && {
        . "$feature" && log "Loaded $feature" || warn "Failed to source $feature"
      }
    done
  done
}

get_app_port() {
  app_name=${1:?Application name required}
  master_json=${MASTER_JSON:-"$SCRIPT_DIR/../master.json"}

  [ -f "$master_json" ] || { err "master.json not found at $master_json"; return 1; }
  command -v jq >/dev/null || { err "jq not installed"; return 1; }

  port=$(jq -r --arg name "$app_name" '.apps[] | select(.name == $name) | .port // empty' "$master_json")
  [ -n "$port" ] || { err "No port for $app_name in $master_json"; return 1; }
  printf '%s\n' "$port"
}

load_feature_modules