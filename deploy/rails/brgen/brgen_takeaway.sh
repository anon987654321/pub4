```zsh
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_failed extended_glob warn_create_global typeset_silent

# Brgen Takeaway setup: Food delivery platform with real-time tracking, restaurant management, and location services on OpenBSD 7.8, unprivileged user

APP_NAME="brgen_takeaway"
BASE_DIR="/home/dev/rails"
SERVER_IP="185.52.176.18"
SCRIPT_DIR="${0:a:h}"

# Generate secure random port between 10000-19999
APP_PORT=$(( 10000 + ( ( $(od -An -N2 -tu2 /dev/urandom) ) % 10000 ) ))

# Source shared functions
if [[ ! -f "${SCRIPT_DIR}/@shared_functions.sh" ]]; then
    print -u2 "Error: Shared functions file not found at ${SCRIPT_DIR}/@shared_functions.sh"
    exit 1
fi
source "${SCRIPT_DIR}/@shared_functions.sh"

# Enhanced function definitions
function log() { print -u2 "[$(date +%Y-%m-%d\ %H:%M:%S)] $@" }
function command_exists() { command -v "$1" >/dev/null 2>&1 }
function install_gem() {
    log "Installing gem: $@"
    if ! gem install "$@"; then
        log "Error: Failed to install gem(s): $@"
        return 1
    fi
}
function check_port_available() {
    local port="$1"
    if command_exists netstat; then
        if netstat -an | grep -q ":$port "; then
            return 1
        fi
    elif command_exists ss; then
        if ss -ln | grep -q ":$port "; then
            return 1
        fi
    fi
    return 0
}
function find_available_port() {
    local base_port=10000
    local max_attempts=1000

    for ((i=0; i<max_attempts; i++)); do
        local test_port=$((base_port + i))
        if check_port_available "$test_port"; then
            echo "$test_port"
            return 0
        fi
    done

    log "Error: Could not find available port after $max_attempts attempts"
    return 1
}

function setup_full_app() {
    local app_name="$1"
    log "Setting up full application: $app_name"

    # Check required commands with better error messages
    local required_commands=(ruby rails node psql)
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log "Error: Required command '$cmd' not found in PATH. Please install it first."
            return 1
        fi
    done

    # Install dependencies with better error handling
    log "Installing bundle dependencies..."
    if ! bundle install; then
        log "Error: Bundle install failed. Check your Gemfile and network connection."
        return 1
    fi

    # Setup database with detailed error reporting
    log "Setting up database..."
    if ! bin/rails db:create; then
        log "Error: Database creation failed. Check database configuration and permissions."
        return 1
    fi
    if ! bin/rails db:migrate; then
        log "Error: Database migration failed. Check migration files and database state."
        return 1
    fi
}

# Use the improved port finding function
APP_PORT=$(find_available_port)
if [[ -z "$APP_PORT" ]]; then
    exit 1
fi
log "Using port: $APP_PORT"
```
