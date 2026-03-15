#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:a:h}"
MASTER_JSON="${MASTER_JSON:-${SCRIPT_DIR}/../master.json}"

typeset -A PORTS

log() {
  print -r -- "$*"
}

error() {
  print -u2 -r -- "❌ $*"
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    error "Missing required command: $cmd"
    exit 1
  }
}

validate_master_json() {
  [[ -f "$MASTER_JSON" ]] || {
    error "master.json not found at: $MASTER_JSON"
    return 1
  }

  jq -e '.apps | type == "array" and length > 0' "$MASTER_JSON" >/dev/null 2>&1 || {
    error "master.json must contain a non-empty .apps array"
    return 1
  }
}

load_ports() {
  local app port
  local ok=true

  while IFS=$'\t' read -r app port; do
    if [[ -z "$app" || -z "$port" ]]; then
      error "Found app with missing name or port"
      ok=false
      continue
    fi

    if [[ ! "$port" =~ '^[1-9][0-9]*$' ]] || (( port < 1 || port > 65535 )); then
      error "Invalid port '$port' for app '$app'"
      ok=false
      continue
    fi

    if [[ -n "${PORTS[$app]-}" ]]; then
      error "Duplicate app name '$app' in master.json"
      ok=false
      continue
    fi

    PORTS[$app]="$port"
  done < <(jq -r '.apps[] | [.name, .port] | @tsv' "$MASTER_JSON")

  $ok || return 1
}

check_duplicate_ports() {
  typeset -A SEEN_BY_PORT
  local app port
  local ok=true

  for app port in ${(kv)PORTS}; do
    if [[ -n "${SEEN_BY_PORT[$port]-}" ]]; then
      error "Port collision on $port: ${SEEN_BY_PORT[$port]} and $app"
      ok=false
      continue
    fi
    SEEN_BY_PORT[$port]="$app"
  done

  $ok || return 1
}

check_expected_port_constants() {
  local ok=true
  local app installer expected installer_port

  for app expected in ${(kv)PORTS}; do
    installer="${SCRIPT_DIR}/${app}/${app}.sh"
    [[ -f "$installer" ]] || continue

    installer_port="$(sed -nE 's/^[[:space:]]*(readonly[[:space:]]+)?PORT=([0-9]+).*/\2/p' "$installer" | head -n1)"
    if [[ -n "$installer_port" && "$installer_port" != "$expected" ]]; then
      error "${installer} sets PORT=${installer_port}, expected ${expected}"
      ok=false
    fi
  done

  $ok || return 1
}

main() {
  log "=== Port Consistency Check ==="
  require_command jq
  validate_master_json
  load_ports
  check_duplicate_ports

  log ""
  log "Ports from ${MASTER_JSON}:"
  for app in ${(ok)PORTS}; do
    log "  - ${app}: ${PORTS[$app]}"
  done

  if check_expected_port_constants; then
    log ""
    log "✅ Port checks passed"
  else
    exit 1
  fi
}

main "$@"
