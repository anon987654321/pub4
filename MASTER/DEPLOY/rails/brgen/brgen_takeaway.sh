#!/usr/bin/env sh
set -eu
set -o pipefail
IFS=$'\n\t'

log() {
    printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

install_gem() {
    log "Installing gem: $*"
    # Suppress documentation, fail fast on error
    if ! gem install --no-document "$@"; then
        log "Error: Failed to install gem(s): $*"
        exit 1
    fi
}

# Detect an available port‑checking utility.
detect_port_checker() {
    for cmd in sockstat netstat ss lsof; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf '%s' "$cmd"
            return 0
        fi
    done
    return 1
}
PORT_CHECKER=$(detect_port_checker) || {
    log "Error: No port‑checking tool found (sockstat, netstat, ss, lsof)"
    exit 1
}

check_port_available() {
    port=$1
    case $PORT_CHECKER in
        sockstat) sockstat -l -4 -p "$port" | grep -qE ":$port\$" && return 1 ;;
        netstat) netstat -an -f inet | grep -qE ":$port[[:space:]]" && return 1 ;;
        ss) ss -ln -4 "sport = :$port" | grep -qE ":$port\$" && return 1 ;;
        lsof) lsof -iTCP:"$port" -sTCP:LISTEN -t >/dev/null && return 1 ;;
        *) return 0 ;;
    esac
    return 0
}

find_available_port() {
    base=${FIND_PORT_BASE:-3000}
    max=${FIND_PORT_MAX:-4000}
    port=$base
    while [ "$port" -le "$max" ]; do
        if check_port_available "$port"; then
            printf '%s\n' "$port"
            return 0
        fi
        port=$((port + 1))
    done
    log "Error: No free port found in range $base‑$max"
    return 1
}

# Resolve script directory safely (handles symlinks)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)

# Load shared helpers
SHARED_FILE="${SCRIPT_DIR}/@shared_functions.sh"
if [ ! -f "$SHARED_FILE" ]; then
    log "Error: Shared functions not found at $SHARED_FILE"
    exit 1
fi
. "$SHARED_FILE"

# Future deployment logic goes here

exit 0