```zsh
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_failed extended_glob warn_create_global typeset_silent

# Brgen Takeaway setup: Food delivery platform with real-time tracking, restaurant management, and location services on OpenBSD 7.8, unprivileged user

APP_NAME="brgen_takeaway"
BASE_DIR="/home/dev/rails"
SCRIPT_DIR="${0:A:h}"

# Required commands validation - only require one port checking tool
required_commands=(gem)
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

# Source shared functions
if [[ ! -f "${SCRIPT_DIR}/@shared_functions.sh" ]]; then
    print -u2 "Error: Shared functions file not found at ${SCRIPT_DIR}/@shared_functions.sh"
    exit 1
fi
source "${SCRIPT_DIR}/@shared_functions.sh" || { print -u2 "Error: Failed to source shared functions"; exit 1 }

# Enhanced function definitions
log() { print -u2 "[$(date +%Y-%m-%dT%H:%M:%S%z)] $@" }
command_exists() { command -v "$1" >/dev/null 2>&1 }
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
            if sockstat -l -4 | awk '{print $3}' | grep -q ":$port\$"; then
                available=1
            fi
            ;;
        netstat)
            if netstat -an -f inet | awk '{print $4}' | grep -q ":$port\$"; then
                available=1
            fi
            ;;
        ss)
            if ss -ln -4 | awk '{print $4}' | grep -q ":$port\$"; then
                available=1
            fi
            ;;
    esac

    return $available
}
find_available_port() {
    local base_port=${FIND_PORT_BASE:-10000}
    local max_port=${FIND_PORT_MAX:-19999}
    local max_attempts=100
    local timeout=30
    local start_time=$SECONDS

    for ((i=0; i<max_attempts; i++)); do
        if (( SECONDS -
