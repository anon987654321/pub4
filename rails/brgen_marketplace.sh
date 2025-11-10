#!/usr/bin/env zsh
set -euo pipefail

# Brgen Marketplace: Adds Solidus e-commerce to existing Brgen app
# This extends brgen.sh - run brgen.sh first to create the base app with Devise

APP_NAME="brgen"
BASE_DIR="/home/brgen"

APP_DIR="${BASE_DIR}/app"
BRGEN_IP="185.52.176.18"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "${SCRIPT_DIR
log "Adding Marketplace features to existing Brgen app (User model from brgen.sh)"

# Navigate to existing brgen app (created by brgen.sh with Devise already configured)

if [[ ! -d "$APP_DIR" ]]; then

  log "ERROR: Brgen app not found at $APP_DIR. Run brgen.sh first."
  exit 1
fi
if [[ ! -f "$APP_DIR/config/application.rb" ]]; then
  log "ERROR: Rails app not initialized. Run brgen.sh first."

  exit 1
fi
cd "$APP_DIR"
log "Working in app directory: $APP_DIR"

command_exists "ruby"
command_exists "node"

command_exists "psql"
command_exists "redis-server"
install_gem "faker"
# Install Solidus e-commerce platform

log "Installing Solidus e-commerce platform"

bundle add solidus
bundle add solidus_stripe
bundle install
# Generate Solidus installation (reuses existing User model from Devise)
bin/rails generate solidus:install --auto-accept

bin/rails db:migrate
# Add custom marketplace models (user:references works because brgen.sh created users table)
bin/rails generate model Vendor name:string description:text user:references verified:boolean

bin/rails generate model VendorProduct vendor:references product:references commission_rate:decimal
bin/rails db:migrate
log "Brgen Marketplace features added to existing app."
log "Run: bin/rails server -p 11006"\/__shared\/@common.sh"}
