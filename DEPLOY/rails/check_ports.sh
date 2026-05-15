#!/usr/bin/env bash
set -euo pipefail

# Port consistency checker for DEPLOY/rails.
# 0 -> success, non-zero -> validation failure.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MASTER_JSON=${MASTER_JSON:-"$SCRIPT_DIR/../master.json"}

log()   { printf '%s\n' "$*"; }
error() { printf '❌ %s\n' "$*" >&2; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || { error "Missing required command: $1"; exit 1; }
}

validate_master_json() {
    [[ -f "$MASTER_JSON" ]] || { error "master.json not found at: $MASTER_JSON"; return 1; }
    jq -e '.apps | type == "array" and length > 0' "$MASTER_JSON" >/dev/null 2>&1 ||
        { error "master.json must contain a non-empty .apps array"; return 1; }
}

load_ports() {
    APPS=()
    declare -gA PORT_OF=()

    while IFS=$'\t' read -r app port; do
        [[ -n "$app" && -n "$port" ]] || { error "App with missing name or port"; return 1; }

        case "$port" in
            ''|*[!0-9]*) error "Invalid port '$port' for app '$app'"; return 1;;
        esac
        (( port >= 1 && port <= 65535 )) || { error "Port out of range '$port' for app '$app'"; return 1; }

        if [[ -n "${PORT_OF[$app]+x}" ]]; then
            error "Duplicate app name '$app' in master.json"
            return 1
        fi

        PORT_OF[$app]=$port
        APPS+=("$app")
    done < <(jq -r '.apps[] | "\(.name)\t\(.port)"' "$MASTER_JSON")
}

check_duplicate_ports() {
    local duplicate=0 app port
    declare -A seen=()

    for app in "${APPS[@]}"; do
        port=${PORT_OF[$app]}
        if [[ -n "${seen[$port]+x}" ]]; then
            error "Port collision on $port: ${seen[$port]} and $app"
            duplicate=1
        else
            seen[$port]=$app
        fi
    done

    return "$duplicate"
}

extract_installer_port() {
    local installer=$1 line
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*(readonly[[:space:]]+)?PORT=([0-9]+) ]]; then
            printf '%s\n' "${BASH_REMATCH[2]}"
            return 0
        fi
    done < "$installer"
    return 1
}

check_expected_port_constants() {
    local mismatch=0 app installer installer_port expected

    for app in "${APPS[@]}"; do
        installer="$SCRIPT_DIR/$app/$app.sh"
        [[ -f "$installer" ]] || continue

        installer_port=$(extract_installer_port "$installer" || true)
        expected=${PORT_OF[$app]}
        if [[ -n "$installer_port" && "$installer_port" != "$expected" ]]; then
            error "$installer sets PORT=${installer_port}, expected ${expected}"
            mismatch=1
        fi
    done

    return "$mismatch"
}

main() {
    log "=== Port Consistency Check ==="
    require_command jq

    validate_master_json
    load_ports
    check_duplicate_ports

    log ""
    log "Ports from ${MASTER_JSON}:"
    local app
    for app in "${APPS[@]}"; do
        log "  - $app: ${PORT_OF[$app]}"
    done

    if check_expected_port_constants; then
        log ""
        log "✅ Port checks passed"
    else
        exit 1
    fi
}

main "$@"
