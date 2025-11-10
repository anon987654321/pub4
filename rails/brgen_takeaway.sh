#!/usr/bin/env zsh
set -euo pipefail

# Brgen Takeaway: Adds food delivery features to existing Brgen app
# This extends brgen.sh - run brgen.sh first to create the base app with Devise

APP_NAME="brgen"
BASE_DIR="/home/brgen"

APP_DIR="${BASE_DIR}/app"
BRGEN_IP="185.52.176.18"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "${SCRIPT_DIR
log "Adding Takeaway features to existing Brgen app (User model from brgen.sh)"

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
# Add takeaway models (user:references works because brgen.sh created users table)

bin/rails generate scaffold Restaurant name:string description:text user:references location:string lat:decimal lng:decimal cuisine:string

bin/rails generate scaffold MenuItem name:string description:text price:decimal restaurant:references category:string available:boolean
bin/rails generate scaffold FoodOrder user:references restaurant:references status:string total:decimal delivery_address:string
bin/rails generate model OrderItem food_order:references menu_item:references quantity:integer
bin/rails db:migrate
log "Brgen Takeaway features added to existing app."
log "Run: bin/rails server -p 11006"\/__shared\/@common.sh"}
