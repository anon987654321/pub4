```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${RAILS_APP_DIR:-/home/dev/rails}"
APP_NAME="privcam"
RAILS_VERSION="7.1.3"
BASE_DIR="${RAILS_BASE_DIR:-/home/dev/rails}"

SERVER_IP="185.52.176.18"
APP_PORT="3000"

source "${SCRIPT_DIR}/@shared_functions.sh"

# Check prerequisites
command_exists "ruby" || { log "Ruby not found"; exit 1; }
command_exists "rails" || { log "Rails not found"; exit 1; }
command_exists "node" || { log "Node.js not found"; exit 1; }
command_exists "psql" || { log "PostgreSQL not found"; exit 1; }

# Check database connectivity
if ! psql -l > /dev/null 2>&1; then
    log "Cannot connect to PostgreSQL. Please check database configuration."
    exit 1
fi

# Install required gems using bundle to ensure version locking
log "Installing required gems..."
if command_exists "bundle"; then
    # Add gems to Gemfile if not already present
    for gem_spec in "faker:2.23.0" "pagy:8.0.2" "stimulus_reflex:3.5.0"; do
        gem_name="${gem_spec%:*}"
        gem_version="${gem_spec#*:}"
        if ! grep -q "gem ['\"]${gem_name}['\"]" Gemfile; then
            echo "gem '${gem_name}', '${gem_version}'" >> Gemfile
            log "Added ${gem_name} to Gemfile"
        fi
    done
    bundle install || { log "Failed to install gems via bundle"; exit 1; }
else
    log "Bundler not found, falling back to gem install"
    gem install faker -v 2.23.0 || { log "Failed to install faker"; exit 1; }
    gem install pagy -v 8.0.2 || { log "Failed to install pagy"; exit 1; }
    gem install stimulus_reflex -v 3.5.0 || { log "Failed to install stimulus_reflex"; exit 1; }
fi

# Patch ApplicationController with Pagy::Backend (idempotent)
if [[ -f "app/controllers/application_controller.rb" ]]; then
    if ! grep -q "Pagy::Backend" "app/controllers/application_controller.rb"; then
        sed -i.bak 's/class ApplicationController < ActionController::Base/a\
  include Pagy::Backend\
/' "app/controllers/application_controller.rb"
        # Clean up backup file
        rm -f "app/controllers/application_controller.rb.bak"
        log "Added Pagy::Backend to ApplicationController"
    fi
else
    log "ApplicationController not found, skipping Pagy patch"
fi

# Generate scaffold for Video with anonymous features (only if not exists)
if [[ ! -f "app/models/video.rb" ]]; then
    log "Generating Video scaffold..."
    if ! rails generate scaffold Video title:string description:text anonymous:boolean user_id:integer; then
        log "Failed to generate Video scaffold"
        exit 1
    fi
else
    log "Video model already exists, skipping scaffold generation"
fi

# Run migrations
log "Running migrations..."
if ! rails db:migrate; then
    log "Failed to run migrations"
    exit 1
fi

# Configure file attachments (Active Storage) if not already installed
if ! rails db:migrate:status 2>/dev/null | grep -q "active_storage"; then
    log "Installing Active Storage..."
    rails active_storage:install || { log "Failed to install Active Storage"; exit 1; }
    rails db:migrate || { log "Failed to run Active Storage migrations"; exit 1; }
else
    log "Active Storage already installed"
fi
```
