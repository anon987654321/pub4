#!/usr/bin/env sh
set -eu
set -o pipefail

APP_NAME="brgen_playlist"
SHARED_FUNCTIONS="shared_functions.sh"

log()   { printf '[INFO] %s\n' "$1"; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }
warn()  { printf '[WARN] %s\n' "$1" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

log "Starting Brgen Playlist setup"

# Load shared utilities
[ -f "$SHARED_FUNCTIONS" ] || error "Missing $SHARED_FUNCTIONS"
. "$SHARED_FUNCTIONS" || error "Failed to source $SHARED_FUNCTIONS"

# Verify required helper
command_exists setup_full_app || error "setup_full_app not available in $SHARED_FUNCTIONS"
setup_full_app "$APP_NAME" || error "setup_full_app failed"

# Verify runtime dependencies
for cmd in ruby bundle rails; do
  command_exists "$cmd" || error "$cmd not found"
done

log "Installing Ruby dependencies"
bundle install || error "bundle install failed"

log "Checking Pagy gem"
bundle info pagy >/dev/null 2>&1 || error "Pagy gem missing"

log "Setting up database"
if ! bin/rails db:create 2>/dev/null; then
  warn "Database may already exist"
fi
bin/rails db:migrate || error "Database migration failed"

log "Generating Playlist models"
bin/rails generate model Playlist::Set name:string description:text user:references \
  || error "Model generation failed"

MODEL_FILE="app/models/playlist/set.rb"
[ -f "$MODEL_FILE" ] || error "Model file $MODEL_FILE not found"

patch_include() {
  target=$1
  pattern=$2
  line=$3

  [ -f "$target" ] || error "Target $target not found"
  if ! grep -qE "$pattern" "$target"; then
    log "Patching $target"
    if command_exists gsed; then
      gsed -i "1i $line" "$target"
    else
      tmp=$(mktemp) && sed "1i $line" "$target" > "$tmp" && mv "$tmp" "$target"
    fi
  else
    log "$line already present in $target"
  fi
}

patch_include "app/controllers/application_controller.rb" 'include[[:space:]]+Pagy::Backend' 'include Pagy::Backend'
patch_include "app/helpers/application_helper.rb"      'include[[:space:]]+Pagy::Frontend' 'include Pagy::Frontend'

log "Brgen Playlist setup completed"