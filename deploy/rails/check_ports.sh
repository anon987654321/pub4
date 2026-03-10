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

# Check for duplicate app names
duplicate_apps=$(jq -r '.apps[].app' "$MASTER_JSON" | sort | uniq -d)
if [[ -n "$duplicate_apps" ]]; then
    echo "❌ Error: Duplicate app names found:"
    echo "$duplicate_apps"
    exit 1
fi

# Parse ports from master.json using jq
declare -A PORTS
while IFS=$'\t' read -r app port; do
    # Skip entries with missing app or port
    if [[ -z "$app" || -z "$port" ]]; then
        echo "❌ Error: Missing app name or port in JSON entry"
        exit 1
    fi

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
errors_found=0

# Check each installer
for app in "${!PORTS[@]}"; do
    installer_name="${INSTALLER_NAMES[$app]:-$app}"
    installer="${SCRIPT_DIR}/${installer_name}.sh"
    port="${PORTS[$app]}"

    if [[ ! -f "$installer" ]]; then
        echo "⚠️  ${app}: installer not found (tried ${installer_name}.sh)"
        missing_installers+=("${installer_name}.sh")
        errors_found=1
        continue
    fi

    # Use more robust port matching that handles comments and variables
    if ! grep -q "[^0-9]${port}[^0-9]\|^${port}[^0-9]\|[^0-9]${port}$\|^${port}$" "$installer"; then
        echo "❌ ${app}: Port $port not found in installer ${installer_name}.sh"
        errors_found=1
    else
        echo "✅ ${app}: Port $port found in installer"
    fi
done

echo ""

# Summary
if [[ ${#missing_installers[@]} -gt 0 ]]; then
    echo "Missing installers:"
    for installer in "${missing_installers[@]}"; do
        echo "  - $installer"
    done
    echo ""
fi

if [[ $errors_found -eq 0 ]]; then
    echo "✅ All checks passed!"
    exit 0
else
    echo "❌ Some checks failed!"
    exit 1
fi
```
