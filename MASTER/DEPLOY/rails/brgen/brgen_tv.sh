#!/usr/bin/env sh
set -eu

# -----------------------------------------------------------------------------
# Brgen TV deployment script – OpenBSD‑first, POSIX‑compatible
# -----------------------------------------------------------------------------

APP_NAME="brgen_tv"
SCRIPT_DIR=$(dirname "$0")
SCRIPT_DIR=$(cd "$SCRIPT_DIR" && pwd)

# -----------------------------------------------------------------------------
# Load shared utilities
# -----------------------------------------------------------------------------
if [ -f "${SCRIPT_DIR}/shared_functions.sh" ]; then
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/shared_functions.sh"
else
    printf 'Error: shared_functions.sh not found\n' >&2
    exit 1
fi

log "Starting Brgen TV setup with video streaming and live broadcasting"

# -----------------------------------------------------------------------------
# Install a package, idempotent and OpenBSD‑first
# -----------------------------------------------------------------------------
install_pkg() {
    pkg=$1
    case "$(uname -s)" in
        OpenBSD) doas pkg_add -I "${pkg}" ;;
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get update -qq && sudo apt-get install -y "${pkg}"
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y "${pkg}"
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y "${pkg}"
            else
                log "Unsupported Linux package manager"
                return 1
            fi
            ;;
        Darwin) brew install "${pkg}" ;;
        *) log "OS not recognized"; return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# Ensure Redis is present and running
# -----------------------------------------------------------------------------
ensure_redis() {
    if ! command -v redis-server >/dev/null 2>&1; then
        log "Redis not found – installing"
        install_pkg redis || {
            log "Redis installation failed – install manually"
            return 1
        }
    fi

    if ! pgrep -x redis-server >/dev/null 2>&1; then
        case "$(uname -s)" in
            OpenBSD) doas rcctl start redis ;;
            Linux)   sudo systemctl enable --now redis-server || sudo systemctl enable --now redis ;;
            Darwin)  brew services start redis ;;
            *)       log "Cannot auto‑start Redis on this OS"; return 1 ;;
        esac
    fi

    if ! redis-cli ping >/dev/null 2>&1; then
        log "Redis not responding – start it manually and rerun"
        return 1
    fi
}

ensure_redis || exit 1

# -----------------------------------------------------------------------------
# Application scaffolding
# -----------------------------------------------------------------------------
setup_full_app "${APP_NAME}" || {
    log "Application setup failed"
    exit 1
}

# -----------------------------------------------------------------------------
# Ruby dependencies
# -----------------------------------------------------------------------------
bundle install || {
    log "bundle install failed"
    exit 1
}

# -----------------------------------------------------------------------------
# Generate Broadcast model
# -----------------------------------------------------------------------------
generate_model "Broadcast title:string description:text is_live:boolean" || {
    log "model generation failed"
    exit 1
}

# -----------------------------------------------------------------------------
# Database migration
# -----------------------------------------------------------------------------
bin/rails db:migrate || {
    log "migration failed"
    exit 1
}

log "Brgen TV setup completed successfully"