

#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_failed extended_glob warn_create_global typeset_silent

APP_NAME="brgen_takeaway"
BASE_DIR="/home/dev/rails"
SCRIPT_DIR="${0:A:h}"

required_commands=(gem sockstat netstat ss)
port_commands=(sockstat netstat ss)
found_port_cmd=""
for cmd in "${port_commands[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        found_port_cmd="$cmd"
        break
    fi
done
if [[ -z "$found_port_cmd" ]]; then
    print -u2 "Error: No port checking tool found (sockstat, netstat, or ss)"
    exit 1
fi

if [[ ! -f "${SCRIPT_DIR}/@shared_functions.sh" ]]; then
    print -u2 "Error: Shared functions file not found at ${SCRIPT_DIR}/@shared_functions.sh"
    exit 1
fi
source "${SCRIPT_DIR}/@shared_functions.sh" || { print -u2 "Error: Failed to source shared functions"; exit 1 }

log() { print -u2 "[$(date +%Y-%m-%dT%H:%M:%S%z)] $@" }
install_gem() {
    log "Installing gem: $@"
    if ! gem install "$@"; then
        log "Error: Failed to install gem(s): $@"
        return 1
    fi
}
check_port_available() {
    local port="$1"
    local available=0

    case "$found_port_cmd" in
        sockstat)
            if sockstat -l -4 -p "$port" | grep -q ":$port\$"; then
                available=1
            fi
            ;;
        netstat)
            if netstat -an -f inet | grep -q ":$port "; then
                available=1
            fi
            ;;
        ss)
            if ss -ln -4 'sport = :'"$port" | grep -q ":$port\$"; then
                available=1
            fi
            ;;
    esac

    return $available
}
find_available_port() {
    local base_port=${FIND_PORT_BASE:-3000}
    local max_port=${FIND_PORT_MAX:-4000}
    local port=$base_port

    while [[ $port -le $max_port ]]; do
        if ! check_port_available "$port"; then
            return $port
        fi
        (( port++ ))
    done
    return 1
}
