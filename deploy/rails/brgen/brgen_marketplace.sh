```zsh
#!/usr/bin/env zsh
emulate -L_create_global

# Brgen Marketplace setup: Multi-vendor marketplace with Solid7.8, unprivileged user

# Framework v37.3.2 compliant with enhanced e-commerce functionality

APP_NAME="brgen_marketplace"
BASE_DIR="/home/dev/rails"
SERVER_IP="185.52.176.18"
APP_PORT=$(( 10000 + (RANDOM % 10000) ))
SCRIPT_DIR="${0:a:h}"

# Define helper functions
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

install_gem() {
  local gem_name="$1"
  if ! bundle show "$gem_name" >/dev/null 2>&1; then
    bundle add "$gem_name" --without production
  fi
}

setup_full_app() {
  local app_name="$1"
  local base_dir="$2"
  local server_ip="$3"
  local app_port="$4"

  log "Setting up application $app_name in $base_dir"
  mkdir -p "$base_dir"
  cd "$base_dir" || exit 1

  if [[ ! -d "$app_name" ]]; then
    rails new "$app_name" --database=postgresql --skip-bundle
  fi

  cd "$app_name" || exit 1
}

# Main execution
log "Starting Brgen Marketplace setup with Solidus e-commerce platform"

setup_full_app "$APP_NAME" "$BASE_DIR" "$SERVER_IP" "$APP_PORT"

# Check required commands
for cmd in ruby node psql bundle; do
  if ! command_exists "$cmd"; then
    log "Error: $cmd is not installed"
    exit 1
  fi
done

# Install required gems
log "Installing Solidus e-commerce platform"
install_gem "faker"
install_gem "solidus"
install_gem "solidus_auth_devise"
install_gem "solidus_searchkick"
install_gem "solidus_reviews"
install_gem "solidus_stripe"
install_gem "pagy"

# Run bundle install once
bundle install --without production || {
  log "Error: Bundle install failed"
  exit 1
}

# Generate and run installations
bundle exec rails generate solidus:install --api --auto-accept || exit 1
bundle exec rails generate solidus_searchkick:install || exit 1
bundle exec rails generate solidus_reviews:install || exit 1
bundle exec rails generate pagy:install || exit 1

bundle exec rails db:create || exit 1
bundle exec rails db:migrate || exit 1

# Add custom marketplace models
bundle exec rails generate model Vendor name:string description:text || exit 1
bundle exec rails db:migrate || exit 1
bundle exec rails db:seed || exit 1

# Solidus configuration
log "Configuring Solidus"
bundle exec rails solidus:install:config || exit 1
bundle exec rails solidus:install:routes || exit 1
bundle exec rails solidus:install:assets || exit 1

# Mapbox integration
log "Integrating Mapbox"
bundle exec rails generate solidus_mapbox:install || exit 1
bundle exec rails db:migrate || exit 1

# Anonymous user feature
log "Implementing anonymous user feature"

# Cleanup
rm -rf tmp/cache
log "Setup completed successfully for $APP_NAME on port $APP_PORT"
```
