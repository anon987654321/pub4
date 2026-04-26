#!/usr/bin/env sh
set -eu

# Port consistency checker for DEPLOY/rails
# 0 → success, non‑zero → validation failure.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MASTER_JSON=${MASTER_JSON:-"$SCRIPT_DIR/../master.json"}

log()   { printf '%s\n' "$*"; }
error() { printf '❌ %s\n' "$*" >&2; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || { error "Missing required command: $1"; exit 1; }
}

validate_master_json() {
    [ -f "$MASTER_JSON" ] || { error "master.json not found at: $MASTER_JSON"; return 1; }
    jq -e '.apps | type == "array" and length > 0' "$MASTER_JSON" >/dev/null 2>&1 ||
        { error "master.json must contain a non‑empty .apps array"; return 1; }
}

# Load app→port mapping into associative arrays.
load_ports() {
    declare -A port_of
    apps_list=''

    jq -r '.apps[] | "\(.name)\t\(.port)"' "$MASTER_JSON" |
    while IFS=$'\t' read -r app port; do
        [ -n "$app" ] && [ -n "$port" ] || { error "App with missing name or port"; return 1; }

        case "$port" in
            ''|*[!0-9]*) error "Invalid port '$port' for app '$app'"; return 1;;
        esac
        [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { error "Port out of range '$port' for app '$app'"; return 1; }

        if [ -n "${port_of[$app]+x}" ]; then
            error "Duplicate app name '$app' in master.json"
            return 1
        fi

        port_of[$app]=$port
        apps_list="${apps_list}${app} "
    done

    # Export for later stages.
    export APPS="$apps_list"
    export PORT_OF_JSON="$(printf '%s\n' "${!port_of[@]}" | while read -r k; do printf '%s=%s\n' "$k" "${port_of[$k]}"; done)"
    # Keep the associative array in a temporary file for subshells that need it.
    export PORT_MAP_FILE=$(mktemp)
    for k in "${!port_of[@]}"; do
        printf '%s=%s\n' "$k" "${port_of[$k]}" >>"$PORT_MAP_FILE"
    done
}

check_duplicate_ports() {
    duplicate=0
    # Build reverse map: port → apps
    declare -A seen
    for app in $APPS; do
        port=$(awk -F= -v a="$app" 'a==$1{print $2}' "$PORT_MAP_FILE")
        if [ -n "${seen[$port]+x}" ]; then
            error "Port collision on $port: ${seen[$port]} and $app"
            duplicate=1
        else
            seen[$port]=$app
        fi
    done
    return $duplicate
}

check_expected_port_constants() {
    mismatch=0
    i=1
    for app in $APPS; do
        installer="$SCRIPT_DIR/$app/$app.sh"
        if [ -f "$installer" ]; then
            installer_port=$(sed -nE 's/^[[:space:]]*(readonly[[:space:]]+)?PORT=([0-9]+).*/\2/p' "$installer" | head -n1)
            expected=$(awk -F= -v a="$app" 'a==$1{print $2}' "$PORT_MAP_FILE")
            if [ -n "$installer_port" ] && [ "$installer_port" != "$expected" ]; then
                error "$installer sets PORT=${installer_port}, expected ${expected}"
                mismatch=1
            fi
        fi
        i=$((i + 1))
    done
    return $mismatch
}

main() {
    log "=== Port Consistency Check ==="
    require_command jq

    validate_master_json
    load_ports
    check_duplicate_ports

    log ""
    log "Ports from ${MASTER_JSON}:"
    for app in $APPS; do
        port=$(awk -F= -v a="$app" 'a==$1{print $2}' "$PORT_MAP_FILE")
        log "  - $app: $port"
    done

    if check_expected_port_constants; then
        log ""
        log "✅ Port checks passed"
    else
        exit 1
    fi
}

main "$@"
