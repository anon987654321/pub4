```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MASTER_JSON="${SCRIPT_DIR}/../master.json"

echo "=== Port Consistency Check ==="
echo ""

# Validate master.json exists
if [[ ! -f "$MASTER_JSON" ]]; then
    echo "❌ Error: master.json not found"
    exit 1
fi

# Validate JSON structure and parse ports
if ! jq -e '.apps | type == "array" and length > 0' "$MASTER_JSON" >/dev/null; then
    echo "❌ Error: Invalid JSON structure or empty apps array in master.json"
    exit 1
fi

# Check for duplicate app names and validate structure in single pass
declare -A PORTS
declare -A APP_NAMES
duplicate_found=false
errors_found=0

while IFS=$'\t' read -r app port; do
    # Skip entries with missing app or port
    if [[ -z "$app" || -z "$port" ]]; then
        echo "❌ Error: Missing app name or port in master.json"
        exit 1
    fi

    # Check for duplicate app names
    if [[ -n "${APP_NAMES[$app]}" ]]; then
        echo "❌ Error: Duplicate app name found: $app"
        duplicate_found=true
    fi
    APP_NAMES["$app"]=1

    # Validate port is numeric and in valid range (no leading zeros)
    if [[ ! "$port" =~ ^[1-9][0-9]*$ ]] || ((port < 1 || port > 65535)); then
        echo "❌ Error: Invalid port '$port' for app '$ then
    exit 1
fi

if [[ "$errors_found" -eq 1 ]]; then
    exit 1
fi

# Check for duplicate ports
declare -A PORT_USAGE
for app in "${!PORTS[@]}"; do
    port="${PORTS[$app]} apps: ${PORT_USAGE[$port]} and $app"
        errors_found=1
    else
        PORT_USAGE["$port"]="$app"
    fi
done

if [[ "$errors_found" -eq 1 ]]; then
    exit 1
fi

echo "Ports from master.json:"
for app in "${!PORTS[@ ""
echo "Checking installers..."
echo ""

# Map app names to installer names (handle special cases)
declare -A INSTALLER_NAMES=(
    ["pubattorney"]="pub_att"
)
```
