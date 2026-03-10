```zsh
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

APP_NAME="baibl"
BASE_DIR="/home/dev/rails"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_IP="185.52.176.18"
APP_PORT=$((10000 + RANDOM % 10000))
MAX_ATTEMPTS=10

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Source shared functions safely
if [[ -f "${SCRIPT_DIR}/@shared_functions.sh" ]]; then
    source "${SCRIPT_DIR}/@shared_functions.sh"
else
    log "Warning: Shared functions file not found at ${SCRIPT_DIR}/@shared_functions.sh"
fi

install_gem() {
    local gem_name="$1"
    log "Checking gem: $gem_name"
    if ! gem list "$gem_name" -i >/dev/null 2>&1; then
        log "Installing gem: $gem_name"
        gem install "$gem_name" || {
            log "Error: Failed to install $gem_name"
            return 1
        }
    else
        log "Gem $gem_name already installed"
    fi
    log "Gem $gem_name is ready"
}

setup_full_app() {
    local app_name="$1"
    log "Setting up full application: $app_name"

    # Validate Rails environment
    if [[ ! -f "bin/rails" ]]; then
        log "Error: bin/rails not found – not a Rails application directory"
        exit 1
    fi
    local rail_ver
    rail_ver=$(rails -v 2>/dev/null | awk '{print $2}')
    if [[ -z $rail_ver ]]; then
        log "Error: Unable to determine Rails version"
        exit 1
    fi
    log "Rails version $rail_ver detected"

    # Database setup with proper error handling and platform compatibility
    if command_exists createdb; then
        for db in "${app_name}_development" "${app_name}_test"; do
            if createdb "$db" 2>/dev/null; then
                log "Database $db created"
            else
                log "Database $db already exists or could not be created"
            fi
        done
    elif command_exists psql; then
        log "Warning: createdb not found, attempting with psql"
        for db in "${app_name}_development" "${app_name}_test"; do
            if psql -lqt | cut -d \| -f 1 | grep -qw "$db"; then
                log "Database $db;" 2>/dev/null; then
                    log "Database $db created using psql"
                else
                    log "Error: Failed to create database $db using psql"
                fi
            fi
        done
    else
        log "Error: Neither createdb nor psql found – cannot create databases"
        exit 1
    fi
}

log "Starting $APP_NAME AI"
```
