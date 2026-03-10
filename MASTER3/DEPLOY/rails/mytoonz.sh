```zsh
#!/usr/bin/env zsh
set -euo pipefail

# MyToonz: AI-Powered Personalized Comic Strip Generator
# Generates authentic comic strips from user's daily stories using Replicate AI

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="mytoonz"

cleanup() {
    log "Cleaning up..."
    # Add any cleanup operations here
}

trap cleanup EXIT INT TERM

if [[ -f "${BASE_DIR}/__shared.sh" ]]; then
    source "${BASE_DIR}/__shared.sh"
else
    echo "Error: __shared.sh not found in ${BASE_DIR}" >&2
    exit 1
fi

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

check_dependencies() {
    log "Checking dependencies..."
    command -v node >/dev/null 2>&1 || { log_error "Node.js is required but not installed."; exit 1; }
    command -v npm >/dev/null 2>&1 || command -v yarn >/dev/null 2>&1 || { log_error "npm or yarn is required but not installed."; exit 1; }
    command -v redis-cli >/dev/null 2>&1 || { log "Warning: Redis CLI is not installed. Some features may not work properly."; }
    command -v git >/dev/null 2>&1 || { log "Warning: git is not installed. Some features may not work properly."; }
    command -v curl >/dev/null 2>&1 || { log "Warning: curl is not installed. Some features may not work properly."; }
    command -v bundle >/dev/null 2>&1 || { log "Warning: bundler is not installed. Some features may not work properly."; }
}

validate_environment() {
    log "Validating environment variables..."
    if [[ -z "${REDIS_URL:-}" ]]; then
        REDIS_URL="redis://localhost:6379"
        log "Warning: REDIS_URL not set, using default: $REDIS_URL"
    fi
    if ! [[ "${REDIS_URL}" =~ ^redis://[^\s/]+ ]]; then
        log_error "Invalid REDIS_URL format. Must start with redis:// followed by hostname"
        exit 1
    fi

    if [[ -z "${REPLICATE_API_TOKEN:-}" ]]; then
        log_error "REPLICATE_API_TOKEN is required but not set"
        exit 1
    fi
}

change_to_app_dir() {
    cd "$BASE_DIR/$APP_NAME" || { log_error "Failed to change directory to $BASE_DIR/$APP_NAME"; exit 1; }
}

setup_frontend() {
    log "Setting up frontend..."
    change_to_app_dir

    if [[ -f "package.json" ]]; then
        if command -v yarn >/dev/null 2>&1; then
            yarn install || { log_error "yarn install failed"; exit 1; }
        else
            npm install || { log_error "npm install failed"; exit 1; }
        fi

        if grep -q "\"build\"" "package.json"; then
            if command -v yarn >/dev/null 2>&1; then
                yarn build || { log_error "yarn build failed"; exit 1; }
            else
                npm run build || { log_error "npm run build failed"; exit 1; }
            fi
        else
            log "Warning: No build script found in package.json, skipping build"
        fi
    else
        log "Warning: package.json not found, skipping npm/yarn install"
    fi
}

setup_backend() {
    log "Setting up backend..."
    change_to_app_dir

    if [[ -f "Gemfile" ]]; then
        bundle install || { log_error "bundle install failed"; exit 1; }
    else
        log "Warning: Gemfile not found, skipping bundle install"
    fi
}

main() {
    log "Starting MyToonz setup..."

    check_dependencies
    validate_environment
    setup_frontend
    setup_backend

    log "MyToonz setup completed successfully!"
}

main "$@"
```
