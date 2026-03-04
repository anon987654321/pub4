#!/usr/bin/env bash
# Quick port consistency checker
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MASTER_JSON="${SCRIPT_DIR}/../master.json"

echo "=== Port Consistency Check ==="
echo ""

# Parse ports from master.json
declare -A PORTS
while IFS= read -r line; do
  if [[ "$line" =~ \"([^\"]+)\":[[:space:]]*\{\"port\":[[:space:]]*([0-9]+) ]]; then
    app="${BASH_REMATCH[1]}"
    port="${BASH_REMATCH[2]}"
    PORTS[$app]=$port
  fi
done < <(sed -n '/^[[:space:]]*"apps":/,/^[[:space:]]*}/p' "$MASTER_JSON")

echo "Ports from master.json:"
for app in "${!PORTS[@]}"; do
  printf "  %-15s : %s\n" "$app" "${PORTS[$app]}"
done

echo ""
echo "Checking installers..."
echo ""

# Check each installer
for app in "${!PORTS[@]}"; do
  # Handle special case: pubattorney -> pub_attorney
  installer_name="${app}"
  if [[ "$app" == "pubattorney" ]]; then
    installer_name="pub_attorney"
  fi
  
  installer="${SCRIPT_DIR}/${installer_name}.sh"
  port="${PORTS[$app]}"
  
  if [[ ! -f "$installer" ]]; then
    echo "⚠️  ${app}: installer not found (tried ${installer_name}.sh)"
    continue
  fi
  
  # Check if port appears in installer
  if grep -q "$port" "$installer" 2>/dev/null; then
    echo "✓  ${app}: port ${port} found in installer"
  else
    echo "✗  ${app}: port ${port} NOT found in installer"
  fi
done

echo ""
echo "=== Check complete ==="
