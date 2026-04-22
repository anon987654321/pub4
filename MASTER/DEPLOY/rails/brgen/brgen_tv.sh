#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Brgen TV deployment script – OpenBSD‑first, POSIX‑compatible
# -----------------------------------------------------------------------------

APP_NAME="brgen_tv"
BASE_DIR="${HOME}/rails"
SERVER_IP="185.52.176.18"
APP_PORT=$((10000 + RANDOM % 10000))
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# -----------------------------------------------------------------------------
# Load shared utilities
# -----------------------------------------------------------------------------
if [[ -f "${SCRIPT_DIR}/shared_functions.sh" ]]; then
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
    local pkg=$1
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
if ! command -v redis-server >/dev/null 2>&1; then
    log "Redis not found – installing"
    install_pkg redis || {
        log "Redis installation failed – install manually"
        exit 1
    }
fi

if ! pgrep -x redis-server >/dev/null 2>&1; then
    case "$(uname -s)" in
        OpenBSD) doas rcctl start redis ;;
        Linux)   sudo systemctl enable --now redis-server || sudo systemctl enable --now redis ;;
        Darwin)  brew services start redis ;;
        *)       log "Cannot auto‑start Redis on this OS"; exit 1 ;;
    esac
fi

if ! redis-cli ping >/dev/null 2>&1; then
    log "Redis not responding – start it manually and rerun"
    exit 1
fi

# -----------------------------------------------------------------------------
# Application scaffolding
# -----------------------------------------------------------------------------
setup_full_app "$APP_NAME" || {
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