

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="/home/dev/rails"
APP_NAME="privcam"
RAILS_VERSION="7.1.3"
BASE_DIR="/home/dev/rails"

SERVER_IP="185.52.176.18"
APP_PORT="3000"

source "${SCRIPT_DIR}/@shared_functions.sh"

# Check prerequisites
command_exists "ruby" || { log "Ruby not found"; exit 1; }
command_exists "rails" || { log "Rails not found"; exit 1; }
command_exists "node" || { log "Node.js not found"; exit 1; }
command_exists "psql" || { log "PostgreSQL not found"; exit 1; }

# Install required gems with version constraints for compatibility
install_gem "faker" "2.23.0" || { log "Failed to install faker"; exit 1; }
install_gem "pagy" "8.0.2" || { log "Failed to install pagy"; exit 1; }
install_gem "stimulus_reflex" "3.5.0" || { log "Failed to install stimulus_reflex"; exit 1; }

# Patch ApplicationController with Pagy::Backend (idempotent)
if ! grep -q "Pagy::Backend" app/controllers/application_controller.rb 2>/dev/null; then
  sed -i 's/class ApplicationController < ActionController::Base/a\
  include Pagy::Backend\
/' app/controllers/application_controller.rb
  rm -f app/controllers/application_controller.rb.bak
fi

# Generate scaffold for Video with anonymous features
log "Generating Video scaffold..."
if ! rails generate scaffold Video title:string description:text anonymous:boolean user_id:integer; then
  log "Failed to generate Video scaffold"
  exit 1
fi

# Run migrations
log "Running migrations..."
if ! rails db:migrate; then
  log "Failed to run migrations"
  exit 1
fi

# Configure file attachments (Active Storage)
log "Setting up Active Storage..."
rails active_storage:install
rails db:migrate

# Add file attachment to Video model
if ! grep -q "has_one_attached :video_file" app/models/video.rb 2>/dev/null; then
  echo -e "\n  has_one_attached :video_file" >> app/models/video.rb
  log "Added file attachment to Video model"
fi
