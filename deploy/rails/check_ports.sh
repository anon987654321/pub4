```bash
#!/usr/bin/env bash
# Quick port consistency checker
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MASTER_JSON="${SCRIPT_DIR}/../master.json"

echo "=== Port Consistency Check ==="
echo ""

# Validate master.json exists
if [[ ! -f "$MASTER_JSON" ]]; then
    echo "❌ Error: master.json not found at $MASTER_JSON"
    exit 1
fi

# Validate JSON structure and parse ports
if ! jq -e '.apps | length > 0' "$MASTER_JSON" >/dev/null; then
    echo "❌ Error: Invalid JSON structure or empty apps array in master.json"
    exit 1
fi

# Parse ports from master.json using jq
declare -A PORTS
while IFS=$'\t' read -r app port; do
    # Validate port is numeric and in valid range
    if [[ ! "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
        echo "❌ Error: Invalid port '$port' for app '$app'"
        exit 1
    fi
    PORTS["$app"]="$port"
done < <(jq -r '.apps[] | [.app, .port] | @tsv' "$MASTER_JSON")

# Check for duplicate ports
declare -A PORT_USAGE
for app in "${!PORTS[@]}"; do
    port="${PORTS[$app]}"
    if [[ -n "${PORT_USAGE[$port]:-}" ]]; then
        echo "❌ Error: Port $port used by multiple apps: ${PORT_USAGE[$port]} and $app"
        exit 1
    fi
    PORT_USAGE["$port"]="$app"
done

echo "Ports from master.json:"
for app in "${!PORTS[@]}"; do
    printf "  %-15s : %s\n" "$app" "${PORTS[$app]}"
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

# Check each installer
for app in "${!PORTS[@]}"; do
    installer_name="${INSTALLER_NAMES[$app]:-$app}"
    installer="${SCRIPT_DIR}/${installer_name}.sh"
    port="${PORTS[$app]}"

    if [[ ! -f "$installer" ]]; then
        echo "⚠️  ${app}: installer not found (tried ${installer_name}.sh)"
        missing_installers+=("${installer_name}.sh")
        continue
    fi

    # Use more robust port matching that handles variables and different contexts
    if grep -q -E "(^|[^0-9])${port}([^0-9]|$)" "$installer"; then
        echo "✓  ${app}: port ${port} found in installer"
    else
        echo "✗  ${app}: port ${port} NOT found in installer"
    fi
done

# Report missing installers summary
if [[ ${#missing_installers[@]} -gt 0 ]]; then
    echo ""
    echo "❌ Missing installers:"
    for installer in "${missing_installers[@]}"; do
        echo "  - $installer"
    done
fi

echo ""
echo "=== Check complete ==="
```
