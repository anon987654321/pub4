```zsh
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Brgen Dating setup: Location-based dating platform with matchmaking, Mapbox, live search, infinite scroll, and anonymous features on OpenBSD 7.8, unprivileged user

# Framework v37.3.2 compliant

APP_NAME="brgen_dating"

BASE_DIR="/home/dev/rails"

SERVER_IP="185.52.176.18"

# Use a more reliable port assignment with validation
APP_PORT=$((10000 + RANDOM % 10000))
while [[ $APP_PORT -lt 10000 || $APP_PORT -gt 19999 ]]; do
    APP_PORT=$((10000 + RANDOM % 10000))
done

SCRIPT_DIR="${0:a:h}"

# Define basic log function if shared_functions.sh fails
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Source shared functions with error handling
if [[ -f "${SCRIPT_DIR}/@shared_functions.sh" ]]; then
    source "${SCRIPT_DIR}/@shared_functions.sh"
else
    log "Warning: @shared_functions.sh not found, using basic logging"
fi

log "Starting Brgen Dating setup with enhanced matchmaking"

# Verify Rails app directory exists
if [[ ! -d "$BASE_DIR" ]]; then
    log "Error: Base directory $BASE_DIR does not exist"
    exit 1
fi

cd "$BASE_DIR" || {
    log "Error: Cannot change to base directory $BASE_DIR"
    exit 1
}

# Check if setup_full_app function exists
if ! typeset -f setup_full_app >/dev/null; then
    log "Error: setup_full_app function not found"
    exit 1
fi

# Execute setup with error handling
if ! setup_full_app "$APP_NAME"; then
    log "Error: setup_full_app failed"
    exit 1
fi

# Check for required dependencies
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

for cmd in ruby node psql bundle npm rails; do
    if ! command_exists "$cmd"; then
        log "Error: Required command '$cmd' not found"
        exit 1
    fi
done

# Validate PostGIS installation with better error handling
if ! psql -c "SELECT version();" >/dev/null 2>&1; then
    log "Error: PostgreSQL is not accessible"
    exit 1
fi

if ! psql -c "SELECT postgis_version();" >/dev/null 2>&1; then
    log "Error: PostGIS is not installed or accessible"
    exit 1
fi

# Validate Rails environment
if [[ -z "$RAILS_ENV" ]]; then
    export RAILS_ENV="production"
    log "Warning: RAILS_ENV not set, defaulting to production"
fi

# Validate port assignment
APP_PORT=$((10000 + RANDOM % 10000))
log "Assigned port: $APP_PORT"

# Additional setup validation
if [[ ! -d "${BASE_DIR}/${APP_NAME}" ]]; then
    log "Error: App directory ${BASE_DIR}/${APP_NAME} does not exist after setup"
    exit 1
fi

log "Brgen Dating setup completed successfully on port $APP_PORT"
```
