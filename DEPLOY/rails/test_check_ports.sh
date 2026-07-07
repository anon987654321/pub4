#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHECK_PORTS="$SCRIPT_DIR/check_ports.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

run_check() {
    MASTER_JSON="$TMP_DIR/master.json" "$CHECK_PORTS" >/tmp/check_ports.out 2>/tmp/check_ports.err
}

assert_passes_valid_config() {
    cp "$SCRIPT_DIR/../master.json" "$TMP_DIR/master.json"
    run_check
}

assert_rejects_duplicate_ports() {
    cat > "$TMP_DIR/master.json" <<'JSON'
{
  "apps": [
    { "name": "amber", "domain": "amber.brgen.no", "port": 61352 },
    { "name": "brgen", "domain": "brgen.no", "port": 61352 },
    { "name": "bsdports", "domain": "bsdports.org", "port": 47312 },
    { "name": "hjerterom", "domain": "hjerterom.brgen.no", "port": 38891 }
  ]
}
JSON
    if run_check; then
        printf 'expected duplicate-port config to fail\n' >&2
        return 1
    fi
}

assert_rejects_invalid_port() {
    cat > "$TMP_DIR/master.json" <<'JSON'
{
  "apps": [
    { "name": "amber", "domain": "amber.brgen.no", "port": 70000 },
    { "name": "brgen", "domain": "brgen.no", "port": 38182 },
    { "name": "bsdports", "domain": "bsdports.org", "port": 47312 },
    { "name": "hjerterom", "domain": "hjerterom.brgen.no", "port": 38891 }
  ]
}
JSON
    if run_check; then
        printf 'expected invalid-port config to fail\n' >&2
        return 1
    fi
}

assert_passes_valid_config
assert_rejects_duplicate_ports
assert_rejects_invalid_port
printf '✅ check_ports tests passed\n'
