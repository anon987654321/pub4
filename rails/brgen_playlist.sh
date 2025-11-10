#!/usr/bin/env zsh
set -euo pipefail

# Brgen Playlist: Adds music playlist features to existing Brgen app
# This extends brgen.sh - run brgen.sh first to create the base app with Devise

APP_NAME="brgen"
BASE_DIR="/home/brgen"

APP_DIR="${BASE_DIR}/app"
BRGEN_IP="185.52.176.18"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "${SCRIPT_DIR
log "Adding Playlist features to existing Brgen app (User model from brgen.sh)"

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
# Add playlist models (user:references works because brgen.sh created users table)

bin/rails generate scaffold Playlist name:string description:text user:references public:boolean

bin/rails generate model PlaylistTrack playlist:references track:references position:integer
bin/rails generate scaffold Track title:string artist:string album:string duration:integer audio_file:attachment user:references
bin/rails db:migrate
log "Brgen Playlist features added to existing app."
log "Run: bin/rails server -p 11006"\/__shared\/@common.sh"}
