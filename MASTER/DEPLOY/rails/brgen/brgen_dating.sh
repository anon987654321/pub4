#!/usr/bin/env sh
# -*- mode: sh; -*-

# Fail fast, propagate errors, treat unset variables as errors, fail pipelines
set -eu -o pipefail
IFS=$(printf '\n\t')

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# --------------------------------------------------------------------
# Configuration (immutable)
# --------------------------------------------------------------------
APP_NAME="brgen_dating"
BASE_DIR="/home/dev/rails"
PORT_MIN=10000
PORT_MAX=19999
SERVER_IP="185.52.176.18"

# --------------------------------------------------------------------
# Load optional shared helpers
# --------------------------------------------------------------------
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SHARED="${SCRIPT_DIR}/@shared_functions.sh"
if [ -r "$SHARED" ]; then
  # shellcheck source=/dev/null
  . "$SHARED"
else
  log "Warning: @shared_functions.sh missing – proceeding with built‑in utilities"
fi

log "Starting ${APP_NAME} setup"

# --------------------------------------------------------------------
# Validate environment
# --------------------------------------------------------------------
# Base directory
if [ ! -d "$BASE_DIR" ]; then
  log "Error: Base directory $BASE_DIR missing"
  exit 1
fi
cd "$BASE_DIR"

# Required command utilities
required_cmds="ruby node psql bundle npm rails sha1sum awk cut"
for cmd in $required_cmds; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "Error: required command '$cmd' not found"
    exit 1
  fi
done

# Application bootstrap function
if ! command -v setup_full_app >/dev/null 2>&1; then
  log "Error: setup_full_app not found in PATH"
  exit 1
fi

if ! setup_full_app "$APP_NAME"; then
  log "Error: setup_full_app failed for $APP_NAME"
  exit 1
fi

# PostgreSQL connectivity and PostGIS extension
if ! psql -c "SELECT version();" >/dev/null 2>&1; then
  log "Error: unable to connect to PostgreSQL"
  exit 1
fi

if ! psql -c "SELECT postgis_version();" >/dev/null 2>&1; then
  log "Error: PostGIS extension missing"
  exit 1
fi

# --------------------------------------------------------------------
# Runtime configuration
# --------------------------------------------------------------------
: "${RAILS_ENV:=production}"
log "RAILS_ENV=$RAILS_ENV"

# Deterministic port derived from SHA1 hash of APP_NAME (first 8 hex chars)
hash_hex=$(printf '%s' "$APP_NAME" | sha1sum | awk '{print $1}' | cut -c1-8)
# shellcheck disable=SC2004
hash_dec=$((16#${hash_hex}))
range=$((PORT_MAX - PORT_MIN + 1))
APP_PORT=$((PORT_MIN + (hash_dec % range)))
log "Assigned deterministic port: $APP_PORT"

# Verify application directory
app_path="${BASE_DIR}/${APP_NAME}"
if [ ! -d "$app_path" ]; then
  log "Error: application directory $app_path missing"
  exit 1
fi

log "Brgen Dating setup completed on port $APP_PORT"
exit 0