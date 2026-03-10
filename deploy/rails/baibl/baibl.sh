```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="baibl"
BASE_DIR="/home/dev/wd"
APP_PORT=$((10000 + RANDOM % 10000))
MAX_ATTEMPTS=10

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Source shared functions safely
if [[ -f "${SCRIPT_DIR}/shared_functions" ]]; then
    source "${SCRIPT_DIR}/shared_functions"
else
    log "Warning: shared functions file not found - proceeding without shared functions"
fi

install_gem() {
    local gem_name="$1"
    if [[ -z "$gem_name" ]]; then
        log "Error: Gem name cannot be empty"
        return 1
    fi

    if ! command_exists gem; then
        log "Error: gem command not found"
        return 1
    fi

    if ! gem list "$gem_name" -i >/dev/null 2>&1; then
        log "Installing gem: $gem_name"
        if ! gem install "$gem_name"; then
            log "Error: Failed to install $gem_name"
            return 1
        fi
        log "Successfully installed gem: $gem_name"
    else
        log "Gem $gem_name already installed"
    fi
}

check_postgresql() {
    if ! command_exists psql; then
        log "Error: psql command not found"
        return 1
    fi

    if ! pg_isready -q; then
        log "Error: PostgreSQL is not running or not accepting connections"
        return 1
    fi
}

setup_full_app() {
    local app_name="$1"

    if [[ -z "$app_name" ]]; then
        log "Error: Application name cannot be empty"
        exit 1
    fi

    log "Setting up full application: $app_name"

    # Validate Rails environment
    if [[ ! -f "bin/rails" ]]; then
        log "Error: bin/rails not found – not a Rails application directory"
        exit 1
    fi

    local rail_ver
    if rail_ver=$(rails -v 2>/dev/null); then
        rail_ver=${rail_ver#* }
        log "Rails version $rail_ver detected"
    else
        log "Error: Unable to determine Rails version - ensure Rails is properly installed"
        exit 1
    fi

    # Check PostgreSQL availability
    if ! check_postgresql; then
        log "Error: PostgreSQL is not available"
        exit 1
    fi

    # Database setup with proper error handling
    local dbs=("${app_name}_development" "${app_name}_test")
    for db in "${dbs[@]}"; do
        if psql -lqt | grep -q "^${db}\s"; then
            log "Database $db already exists"
        else
            log "Creating database: $db"
            if ! createdb "$db"; then
                log "Error: Failed to create database $db"
                exit 1
            fi
            log "Successfully created database: $db"
        fi
    done

    # Install dependencies
    log "Installing bundle dependencies"
    if ! bundle install; then
        log "Error: Bundle install failed"
        exit 1
    fi

    # Run migrations
    log "Running database migrations"
    if ! bin/rails db:migrate; then
        log "Error: Database migration failed"
        exit 1
    fi

    log "Application $app_name setup completed successfully"
}
```
