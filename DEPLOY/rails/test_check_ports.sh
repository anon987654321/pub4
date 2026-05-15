#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHECK_PORTS="$SCRIPT_DIR/check_ports.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

write_master_json() {
    cat > "$TMP_DIR/master.json"
}

run_check() {
    MASTER_JSON="$TMP_DIR/master.json" "$CHECK_PORTS" >/tmp/check_ports.out 2>/tmp/check_ports.err
}

assert_passes_valid_config() {
    write_master_json <<'JSON'
{
  "apps": [
    { "name": "amber", "port": 4010 },
    { "name": "baibl", "port": 4011 }
  ]
}
JSON
    run_check
}

assert_rejects_duplicate_ports() {
    write_master_json <<'JSON'
{
  "apps": [
    { "name": "amber", "port": 4010 },
    { "name": "baibl", "port": 4010 }
  ]
}
JSON
    if run_check; then
        printf 'expected duplicate-port config to fail\n' >&2
        return 1
    fi
}

assert_rejects_invalid_port() {
    write_master_json <<'JSON'
{
  "apps": [
    { "name": "amber", "port": 70000 }
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
