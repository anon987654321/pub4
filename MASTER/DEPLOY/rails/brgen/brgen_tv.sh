```sh
#!/bin/bash

set -euo pipefail

APP_NAME="brgen_tv"
BASE_DIR="${HOME}/rails"
SERVER_IP="185.52.176.18"
APP_PORT=$((10000 + RANDOM % 10000))
SCRIPT_DIR=$(dirname "$0")

if [ -f "${SCRIPT_DIR}/shared_functions.sh" ]; then
    . "${SCRIPT_DIR}/shared_functions.sh"
else
    echo "Error: shared_functions.sh not found" >&2
    exit 1
fi

log "Starting Brgen TV setup with video streaming and live broadcasting"

# Detect OS and install Redis appropriately
if ! command -v redis-server >/dev/null 2>&1; then
    log "Installing Redis..."
    case "$(uname -s)" in
        OpenBSD)
            if ! doas pkg_add redis; then
                log "Failed to install Redis. Please install manually via 'pkg_add redis'"
                exit 1
            fi
            ;;
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                if ! sudo apt-get update || ! sudo apt-get install -y redis-server; then
                    log "Failed to install Redis via apt-get"
                    exit 1
                fi
                sudo systemctl enable redis-server
                sudo systemctl start redis-server
            elif command -v yum >/dev/null 2>&1; then
                if ! sudo yum install -y redis; then
                    log "Failed to install Redis via yum"
                    exit 1
                fi
                sudo systemctl enable redis
                sudo systemctl start redis
            else
                log "Unsupported Linux distribution. Please install Redis manually."
                exit 1
            fi
            ;;
        Darwin)
            if command -v brew >/dev/null 2>&1; then
                if ! brew install redis; then
                    log "Failed to install Redis via Homebrew"
                    exit 1
                fi
                brew services start redis
            else
                log "Homebrew not found. Please install Redis manually or install Homebrew first."
                exit 1
            fi
            ;;
        *)
            log "Unsupported operating system. Please install Redis manually."
            exit 1
            ;;
    esac
fi

# Verify Redis is running
if ! command -v redis-cli >/dev/null 2>&1 || ! redis-cli ping >/dev/null 2>&1; then
    log "Redis is not running. Please start Redis manually and rerun the script."
    exit 1
fi

if ! setup_full_app "$APP_NAME"; then
    log "Failed to setup application"
    exit 1
fi

# Install gems using bundler
if ! bundle install; then
    log "Failed to install gems"
    exit 1
fi

if ! generate_model "Broadcast title:string description:text is_live:boolean"; then
    log "Failed to generate broadcast model"
    exit 1
fi

if ! bin/rails db:migrate; then
    log "Failed to run database migrations"
    exit 1
fi

log "Brgen TV setup completed successfully"
```
