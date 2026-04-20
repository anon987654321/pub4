#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_failed extended_glob warn_create_global typeset_silent

APP_NAME='brgen_takeaway'
BASE_DIR='/home/dev/rails'
SCRIPT_DIR="${0:A:h}"

log() { print -u2 "[$(date +%Y-%m-%dT%H:%M:%S%z)] $*"; }

install_gem() {
    log "Installing gem: $*"
    gem install "$@" || { log "Error: Failed to install gem(s): $*"; return 1; }
}

check_port_available() {
    local port=$1 available=0
    case $found_port_cmd in
        sockstat)
            if sockstat -l -4 -p "$port" | grep -q ":$port\$"; then
                available=1
            fi
            ;;
        netstat)
            if netstat -an -f inet | grep -q ":$port "; then                available=1
            fi
            ;;
        ss)
            if ss -ln -4 "sport = :$port" | grep -q ":$port\$"; then                available=1
            fi
            ;;
    esac
    return $available
}

find_available_port() {
    local base_port=${FIND_PORT_BASE:-3000}
    local max_port=${FIND_PORT_MAX:-4000}
    local port=$base_port

    while ((port <= max_port)); do
        if ! check_port_available "$port"; then
            print -r -- "$port"
            return 0
        fi
        ((port++))
    done
    return 1
}

# locate a port checker
found_port_cmd=
for cmd in sockstat netstat ss; do
    if command -v "$cmd" >/dev/null 2>&1; then
        found_port_cmd=$cmd        break
    fi
done
[[ -z $found_port_cmd ]] && { log "Error: No port checking tool found (sockstat, netstat, or ss)"; exit 1; }

# ensure shared functions exist
[[ -f "${SCRIPT_DIR}/@shared_functions.sh" ]] || { log "Error: Shared functions file not found at ${SCRIPT_DIR}/@shared_functions.sh"; exit 1; }
source "${SCRIPT_DIR}/@shared_functions.sh" || { log "Error: Failed to source shared functions"; exit 1; }

# placeholder for further logic...