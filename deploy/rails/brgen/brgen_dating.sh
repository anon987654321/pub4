

#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Brgen Dating setup: Location-based dating platform with matchmaking, Mapbox, live search, infinite scroll, and anonymous features on OpenBSD 7.8, unprivileged user

# Framework v37.3.2 compliant

APP_NAME="brgen_dating"

BASE_DIR="/home/dev/rails"

SERVER_IP="185.52.176.18"

# Use a more reliable port assignment with validation
APP_PORT=$((10000 + RANDOM % 10000))
while [[ $APP_PORT -lt 10000 || $APP_PORT -gt 19999 ]]; do
    APP_PORT=$((10000 + RANDOM % 10000))
done

SCRIPT_DIR="${0:a:h}"

source "${SCRIPT_DIR}/@shared_functions.sh"

log "Starting Brgen Dating setup with enhanced matchmaking"

# Check if setup_full_app function exists
if ! typeset -f setup_full_app >/dev/null; then
    log "Error: setup_full_app function not found in shared_functions.sh"
    exit 1
fi

setup_full_app "$APP_NAME"

# Check for required dependencies
command_exists "ruby"
command_exists "node"
command_exists "psql"

# Validate PostGIS installation
if ! psql -l | grep -q template_postgis; then
    log "Error: PostGIS extension not found. Please install PostGIS first."
    exit 1
fi

# Redis optional - using Solid Cable for ActionCable (Rails 8 default)
install_gem "faker"

# Setup Rails 8 authentication - check if authentication is already set up
if [[ ! -f "app/models/session.rb" && ! -f "app/models/user.rb" ]]; then
    if ! bin/rails generate authentication; then
        log "Error: Failed to generate authentication"
        exit 1
    fi
    if ! bin/rails db:migrate; then
        log "Error: Failed to migrate database for authentication"
        exit 1
    fi
fi

# Patch ApplicationController with Pagy::Backend (idempotent)
if [[ -f "app/controllers/application_controller.rb" ]]; then
    if ! grep -q "include Pagy::Backend" app/controllers/application_controller.rb 2>/dev/null; then
        if ! sed -i '1,/class ApplicationController < ActionController::Base/!b; /class
```
