```zsh
#!/usr/bin/env zsh
set -euo pipefail

# Shared functions for Rails applications
SCRIPT_DIR="${0:a:h}"

# Logging function
log() {
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Source all feature files with error handling
for feature_file in "${SCRIPT_DIR}"/@*_features.sh "${SCRIPT_DIR}"/@stimulus_controllers/*.sh; do
    if [[ -f "$feature_file" ]]; then
        if ! source "$feature_file" 2>&1 | while read -r line; do
            log "ERROR: Failed to source $feature_file: $line"
        done; then
            log "WARNING: Failed to source $feature_file, continuing..."
        fi
    fi
done

# Get application port from master.json
# Usage: get_app_port "brgen" -> 10001
get_app_port() {
    local app_name="$1"
    local master_json="${MASTER_JSON}"

    if [[ -z "$master_json" ]]; then
        master_json="${SCRIPT_DIR}/../master.json"
    fi

    if [[ -z "$app_name" ]]; then
        log "ERROR: Application name is required"
        return 1
    fi

    if [[ ! -f "$master_json" ]]; then
        log "ERROR: master.json not found at $master_json"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        log "ERROR: jq is required to parse master.json but not installed"
        return 1
    fi

    local port
    if ! port=$(jq -e --arg app_name "$app_name" '.apps[] | select(.name == $app_name) | .port' "$master_json" 2>/dev/null); then
        if jq -e --arg app_name "$app_name" '.apps[] | select(.name == $app_name)' "$master_json" >/dev/null 2>&1; then
            log "ERROR: Application '$app_name' found in master.json but no port defined"
        else
            log "ERROR: Application '$app_name' not found in master.json"
        fi
        return 1
    fi

    echo "$port"
}
```
