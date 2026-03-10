```zsh
#!/usr/bin/env zsh
set -euo pipefail

# Shared functions for Rails applications
SCRIPT_DIR="${0:a:h}"

# Source all feature files with consolidated check
for feature_file in "${SCRIPT_DIR}"/@*_features.sh "${SCRIPT_DIR}"/@stimulus_controllers/*.sh; do
    if [[ -f "$feature_file" ]]; then
        source "$feature_file" || {
            log "ERROR: Failed to source $feature_file"
            exit 1
        }
    fi
done

# Logging function
log() {
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Get application port from master.json
# Usage: get_app_port "brgen" -> 10001
get_app_port() {
    local app_name="$1"
    local master_json="${SCRIPT_DIR}/../master.json"

    if [[ -z "$app_name" ]]; then
        log "ERROR: Application name is required"
        exit 1
    fi

    # Try to parse from master.json using jq
    if [[ -f "$master_json" ]]; then
        if command -v jq >/dev/null 2>&1; then
            local port
            port=$(jq -e --arg app_name "$app_name" '.apps[] | select(.name == $app_name) | .port' "$master_json" 2>/dev/null) || {
                log "ERROR: Port not found for application '$app_name' in master.json"
                exit 1
            }
            echo "$port"
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
