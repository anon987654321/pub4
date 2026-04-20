#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global# Constants
APP_NAME="brgen_dating"
BASE_DIR="/home/dev/rails"
PORT_MIN=10000
PORT_MAX=19999
SERVER_IP="185.52.176.18"

# Log with formatting
log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

SCRIPT_DIR="${0:a:h}"
if [[ -f "${SCRIPT_DIR}/@shared_functions.sh" ]]; then
  source "${SCRIPT_DIR}/@shared_functions.sh"
else
  log "Warning: @shared_functions.sh missing; using minimal logging"
fi

log "Starting ${APP_NAME} setup with enhanced matchmaking"

# Guard clauses[[ -d "$BASE_DIR" ]] || { log "Error: Base directory $BASE_DIR missing"; exit 1; }
cd "$BASE_DIR" || { log "Error: Cannot cd to $BASE_DIR"; exit 1; }

type -f setup_full_app >/dev/null || { log "Error: setup_full_app missing"; exit 1; }

if ! setup_full_app "$APP_NAME"; then
  log "Error: setup_full_app failed"
  exit 1
fi

command_exists() { command -v "$1" >/dev/null 2>&1; }
for cmd in ruby node psql bundle npm rails; do
  command_exists "$cmd" || { log "Error: Command '$cmd' not found"; exit 1; }
done

psql -c "SELECT version();" >/dev/null || { log "Error: PostgreSQL inaccessible"; exit 1; }
psql -c "SELECT postgis_version();" >/dev/null || { log "Error: PostGIS missing"; exit 1; }

: "${RAILS_ENV:=production}"
log "RAILS_ENV=$RAILS_ENV"

# Deterministic port assignment
APP_PORT=$((PORT_MIN + RANDOM % (PORT_MAX - PORT_MIN + 1)))
log "Assigned port: $APP_PORT"

[[ -d "${BASE_DIR}/${APP_NAME}" ]] || { log "Error: App directory missing"; exit 1; }

log "Brgen Dating setup completed on port $APP_PORT"
exit 0