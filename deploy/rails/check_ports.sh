```bash
wd)"
MASTER_JSON="${SCRIPT_DIR}/../master.json"

echo "=== Port Consistency Check ==="
echo ""

# Validate master.json exists
if [[ ! -f "$MASTER_JSON" ]]; then
    echo "❌ Error: master.json not found at $MASTER_JSON"
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

    # Validate port is numeric and in valid range
    if [[ ! "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
        echo "❌ Error: Invalid port '$port' for app '$app'"
        exit 1
    fi

    PORTS["$app"]="$port"
done < <(jq -r '.apps[] | [.app, .port] | @tsv' "$MASTER_JSON")

if [[ "$duplicate_found" == true ]]; then
    exit 1
fi

# Check for duplicate ports
declare -A PORT_USAGE
for app in "${!PORTS[@]}"; do
    port="${PORTS[$app]}"
    if [[ -n "${PORT_USAGE[$port]}" ]]; then
        echo "❌ Error: Port $port used by multiple apps: ${PORT_USAGE[$port]} and $app"
        errors_found=1
    else
        PORT_USAGE["$port"]="$app"
    fi
done

if [[ "$errors_found" -eq 1 ]]; then
    exit 1
fi

echo "Ports from master.json:"
for app in "${!PORTS[@]}"; do
    printf "%-20s %s\n" "$app" "${PORTS[$app]}"
done

echo ""
echo "Checking installers..."
echo ""

# Map app names to installer names (handle special cases)
declare -A INSTALLER_NAMES=(
    ["pubattorney"]="pub_attorney"
)

# Track missing installers
missing_installers=()
errors_found=0

for app in "${!PORTS[@]}"; do
    installer_name="${INSTALLER_NAMES[$app]:-$app}"
    installer_path="${SCRIPT_DIR}/${installer_name}.sh"

    if [[ ! -f "$installer_path" ]]; then
        missing_installers+=("$installer_name")
        echo "❌ Missing installer: $installer_name.sh"
        errors_found=1
    fi
done

if [[ ${#missing_installers[@]} -gt 0 ]]; then
    echo ""
    echo "Missing installers: ${missing_installers[*]}"
fi

if [[ "$errors_found" -eq 1 ]]; then
    exit 1
fi

echo "✅ All checks passed!"
```
