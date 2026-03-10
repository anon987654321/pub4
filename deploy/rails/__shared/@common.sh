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
    command -v "$1" >/dev/null 2>&1 || {
        log "ERROR: $1 is required but not installed"
        exit 1
    }
}

# Get port for an app from master.json with validation
# Usage: get_app_port "brgen" -> 10001
get_app_port() {
    local app_name="$1"
    local master_json="${SCRIPT_DIR}/../master.json"

    # Default ports (fallback if master.json not found or parsing fails)
    typeset -A default_ports
    default_ports=(
        [brgen]=10001
        [pubattorney]=10002
        [bsdports]=10003
        [hjerterom]=10004
        [privcam]=10005
        [amber]=10006
        [blognet]=10007
    )

    # Validate app_name
    if [[ -z "$app_name" ]]; then
        log "ERROR: Application name is required"
        exit 1
    fi

    # Try to parse from master.json using jq if available
    if [[ -f "$master_json" ]]; then
        if command_exists jq; then
            local port=$(jq -e --arg app "$app_name" '.[$app].port' "$master_json" 2>/dev/null || echo "")
            if [[ -n "$port" && "$port" != "null" && "$port" =~ ^[0-9]+$ && "$port" -ge 1024 && "$port" -le 65535 ]]; then
                echo "$port"
                return 0
            fi
        else
            # Fallback to grep/sed if jq not available
            local port=$(grep -E "\"${app_name}\".*\"port\"" "$master_json" | \
                         sed -E 's/.*"port":[[:space:]]*([0-9]+).*/\1/')
            if [[ -n "$port" && "$port" =~ ^[0-9]+$ && "$port" -ge 1024 && "$port" -le 65535 ]]; then
                echo "$port"
                return 0
            fi
        fi
    fi

    # Fallback to default ports
    if [[ -n "${default_ports[$app_name]}" ]]; then
        echo "${default_ports[$app_name]}"
        return 0
    fi

    log "ERROR: Could not determine port for application '$app_name'"
    exit 1
}
```
