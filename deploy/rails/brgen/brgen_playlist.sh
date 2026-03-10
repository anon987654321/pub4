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

setup_full_app "$APP_NAME" || error "Failed to setup full app"

command_exists "ruby" || error "Ruby not found"
command_exists "bundle" || error "Bundler not found"
command_exists "rails" || error "Rails not found"

log "Setting up Ruby environment and installing dependencies"
bundle install || error "Bundle install failed"

log "Database setup"
bin/rails db:create || warn "Database creation may have failed (possibly already exists)"
bin/rails db:migrate || error "Database migration failed"

log "Generating playlist models"
bin/rails generate model Playlist::Set name:string description:text user:references || error "Playlist model generation failed"

log "Checking if Pagy gem is available"
if ! bundle info pagy >/dev/null 2>&1; then
    error "Pagy gem not found in bundle"
fi

patch_controller() {
    local file="app/controllers/application_controller.rb"
    [[ -f "$file" ]] || error "ApplicationController not found"

    if ! grep -q "include Pagy::Backend" "$file"; then
        if sed --version 2>/dev/null | grep -q "GNU sed"; then
            sed -i '1i\  include Pagy::Backend' "$file" || error "Failed to patch ApplicationController"
        else
            sed -i '' '1i\
  include Pagy::Backend
' "$file" || error "Failed to patch ApplicationController"
        fi
    fi
}

patch_helper() {
    local file="app/helpers/application_helper.rb"
    [[ -f "$file" ]] || error "ApplicationHelper not found"

    if ! grep -q "include Pagy::Frontend" "$file"; then
        if sed --version 2>/dev/null | grep -q "GNU sed"; then
            sed -i '1i\  include Pagy::Frontend' "$file" || error "Failed to patch ApplicationHelper"
        else
            sed -i '' '1i\
  include Pagy::Frontend
' "$file" || error "Failed to patch ApplicationHelper"
        fi
    fi
}

patch_controller
patch_helper
```
