#!/usr/bin/env sh
set -euo pipefail

# MyToonz – AI‑powered personalized comic strip generator
# Deploys the Rails + Node frontend, validates environment and dependencies.

readonly BASE_DIR=$(cd "$(dirname "$0")" && pwd)
readonly APP_NAME=mytoonz
readonly APP_DIR=$BASE_DIR/$APP_NAME

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}
log_error() {
    printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# source shared helpers if present
if [ -f "$BASE_DIR/__shared.sh" ]; then
    . "$BASE_DIR/__shared.sh"
else
    log_error "__shared.sh missing in $BASE_DIR"
    exit 1
fi

command_exists() { command -v "$1" >/dev/null 2>&1; }

check_dependencies() {
    log "Checking required commands…"
    for cmd in node npm yarn redis-cli git curl bundle; do
        if ! command_exists "$cmd"; then
            case $cmd in
                node)   log_error "Node.js not installed"; exit 1 ;;
                npm|yarn) log_error "npm or yarn not installed"; exit 1 ;;
                *)      log "Warning: $cmd missing – related features disabled" ;;
            esac
        fi
    done
}

validate_environment() {
    log "Validating environment…"
    : "${REDIS_URL:=redis://localhost:6379}"
    case $REDIS_URL in
        redis://*) ;; # ok
        *) log_error "REDIS_URL must start with redis://"; exit 1 ;;
    esac
    : "${REPLICATE_API_TOKEN:?REPLICATE_API_TOKEN required}"
}

run_pkg_manager() {
    if command_exists yarn; then
        yarn "$@"
    else
        npm "$@"
    fi
}

setup_frontend() {
    log "Setting up frontend…"
    cd "$APP_DIR" || { log_error "Cannot cd $APP_DIR"; exit 1; }

    if [ -f package.json ]; then
        run_pkg_manager install || { log_error "Package install failed"; exit 1; }
        if grep -q '"build"' package.json; then
            run_pkg_manager run build || { log_error "Build failed"; exit 1; }
        else
            log "No build script – skipping"
        fi
    else
        log "No package.json – skipping frontend"
    fi
}

setup_backend() {
    log "Setting up backend…"
    cd "$APP_DIR" || { log_error "Cannot cd $APP_DIR"; exit 1; }

    if [ -f Gemfile ]; then
        bundle install || { log_error "bundle install failed"; exit 1; }
    else
        log "No Gemfile – skipping backend"
    fi
}

cleanup() { log "Cleanup complete"; }
trap cleanup EXIT INT TERM

main() {
    log "Starting MyToonz deployment"
    check_dependencies
    validate_environment
    setup_frontend
    setup_backend
    log "MyToonz setup finished"
}

main "$@"
