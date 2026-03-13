```zsh
#!/usr/bin/env zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

APP_NAME="brgen_playlist"
SHARED_FUNCTIONS="/shared_functions.sh"

log() { echo "[INFO] $1"; }
error() { echo "[ERROR] $1" >&2; exit 1; }
warn() { echo "[WARN] $1" >&2; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

log "Starting Brgen Playlist setup with music streaming and collaboration features"

[[ -f "$SHARED_FUNCTIONS" ]] || error "Shared functions file not found: $SHARED_FUNCTIONS"
source "$SHARED_FUNCTIONS" || error "Failed to source shared functions"

# Check if setup_full_app function exists after sourcing shared functions
if ! typeset -f setup_full_app >/dev/null; then
    error "setup_full_app function not found in shared functions"
fi

setup_full_app "$APP_NAME" || error "Failed to setup full app"

command_exists "ruby" || error "Ruby not found"
command_exists "bundle" || error "Bundler not found"
command_exists "rails" || error "Rails not found"

log "Setting up Ruby environment and installing dependencies"
bundle install || error "Bundle install failed"

log "Checking if Pagy gem is available"
if ! bundle info pagy >/dev/null 2>&1; then
    error "Pagy gem not found in bundle"
fi

log "Database setup"
if ! bin/rails db:create 2>/dev/null; then
    warn "Database creation may have failed (possibly already exists)"
fi
bin/rails db:migrate || error "Database migration failed"

log "Generating playlist models"
bin/rails generate model Playlist::Set name:string description:text user:references || error "Playlist model generation failed"

# Verify model was created
MODEL_FILE="app/models/playlist/set.rb"
[[ -f "$MODEL_FILE" ]] || error "Generated model file not found: $MODEL_FILE"

patch_controller() {
    local file="app/controllers/application_controller.rb"
    [[ -f "$file" ]] || error "ApplicationController not found"

    # More robust check for existing include
    if ! grep -q "include[[:space:]]\+Pagy::Backend" "$file" 2>/dev/null; then
        log "Patching ApplicationController with Pagy::Backend"
        if command_exists gsed; then
            gsed -i '1i include Pagy::Backend' "$file" || error "Failed to patch ApplicationController"
        elif sed --version 2>/dev/null | grep -q "GNU sed"; then
            sed -i '1i include Pagy::Backend' "$file" || error "Failed to patch ApplicationController"
        else
            sed -i '' '1i\
include Pagy::Backend
' "$file" || error "Failed to patch ApplicationController"
        fi
    else
        log "Pagy::Backend already included in ApplicationController"
    fi
}

patch_helper() {
    local file="app/helpers/application_helper.rb"
    [[ -f "$file" ]] || error "ApplicationHelper not found"

    # More robust check for existing include
    if ! grep -q "include[[:space:]]\+Pagy::Frontend" "$file" 2>/dev/null; then
        log "Patching ApplicationHelper with Pagy::Frontend"
        if command_exists gsed; then
            gsed -i '1i include Pagy::Frontend' "$file" || error "Failed to patch ApplicationHelper"
        elif sed --version 2>/dev/null | grep -q "GNU sed"; then
            sed -i '1i include Pagy::Frontend' "$file" || error "Failed to patch ApplicationHelper"
        else
            sed -i '' '1i\
include Pagy::Frontend
' "$file" || error "Failed to patch ApplicationHelper"
        fi
    else
        log "Pagy::Frontend already included in ApplicationHelper"
    fi
}

# Execute patching functions
patch_controller
patch_helper

log "Brgen Playlist setup completed successfully"
```
