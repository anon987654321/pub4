```zsh
#!/usr/bin/env zsh
set -euo pipefail

# Shared functions for Rails applications
SCRIPT_DIR="${0:a:h}"

# Source all feature files with consolidated check
for feature_file in "${SCRIPT_DIR}"/@*_features.sh "${SCRIPT_DIR}"/@stimulus_controllers.sh; do
    if [[ -f "$feature_file" ]]; then
        source "$feature_file"
    fi
done

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

validate_port() {
    [[ "$1" =~ ^[0-9]+$ && "$1" -ge 1024 && "$1" -le 65535 ]] || {
        log "ERROR: Invalid port number: $1"
        exit 1
    }
}

# Get port for an app from master.json with validation
# Usage: get_app_port "brgen" -> 10001
get_app_port() {
    local app_name="$1"
    local master_json="${SCRIPT_DIR}/../master.json"
    local port

    # Validate app_name
    if [[ -z "$app_name" ]]; then
        log "ERROR: Application name is required"
        exit 1
    fi

    # Try to parse from master.json using jq
    if [[ -f "$master_json" ]]; then
        if command_exists jq; then
            port=$(jq -e --arg app "$app_name" '.[$app].port' "$master_json" 2>/dev/null || echo "")
            if [[ -n "$port" && "$port" != "null" ]]; then
                validate_port "$port"
                echo "$port"
                return 0
            else
                log "ERROR: Port not found for application '$app_name' in master.json"
                exit 1
            fi
        else
            log "ERROR: jq is required to parse master.json but not installed"
            exit 1
        fi
    else
        log "ERROR: master.json not found at $master_json"
        exit 1
    fi
}
```
