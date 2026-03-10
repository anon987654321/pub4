```zsh
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Blognet: Multi-blog platform with AI content generation

APP_NAME="blognet"

BASE_DIR="/home/dev/rails"

SERVER_IP="185.52.176.18"

# Find available port using modern ss command with robust pattern matching
find_available_port() {
  local port=3000
  while ss -tuln | awk '{print $5}' | grep -q ":${port}$"; do
    port=$((port + 1))
    [[ $port -gt 65535 ]] && { echo "No available ports found" >&2; exit 1; }
  done
  echo $port
}
APP_PORT=$(find_available_port) || exit 1

SCRIPT_DIR="${0:a:h}"

source "${SCRIPT_DIR}/@shared_functions.sh"

# Enhanced idempotency check with proper exit code handling
check_app_fully_configured() {
  [[ -f "app/models/blog.rb" ]] && \
  [[ -f "app/models/user.rb" ]] && \
  [[ -f "db/schema.rb" ]] && \
  grep -q "include Pagy::Backend" app/controllers/application_controller.rb 2>/dev/null && \
  grep -q "include Pagy::Frontend" app/helpers/application_helper.rb 2>/dev/null && \
  bundle show solid_queue >/dev/null 2>&1
}

check_app_fully_configured && exit 0

setup_full_app "$APP_NAME"

# Safe Gemfile modification with duplicate prevention and atomic writes
add_gems_if_missing() {
  [[ -f "Gemfile" ]] || { echo "Gemfile not found" >&2; exit 1; }

  local gem_list=(
    "solid_queue"
    "solid_cache"
    "solid_cable"
    "propshaft"
    "turbo-rails"
    "stimulus-rails"
    "devise"
    "devise-guests"
    "acts_as_tenant"
    "pagy"
    "langchainrb_rails"
    "rhino-editor"
    "chartkick"
    "geocoder"
  )

  local temp_gemfile="$(mktemp)"

  # Copy existing Gemfile
  cp Gemfile "$temp_gemfile" || { echo "Failed to create temp Gemfile" >&2; exit 1; }

  for gem in "${gem_list[@]}"; do
    grep -q "$gem" "$temp_gemfile" 2>/dev/null || echo "gem \"$gem\"" >> "$temp_gemfile"
  done

  if ! grep -q "group :development do" "$temp_gemfile"; then
    cat >> "$temp_gemfile" << 'GEMFILE'
group :development do
  gem "debug"
end
GEMFILE
  elif ! grep -q "gem \"debug\"" "$temp_gemfile"; then
    sed -i '/group :development do/a\  gem "debug"' "$temp_gemfile" || { echo "Failed to add debug gem" >&2; exit 1; }
  fi

  # Atomic replacement
  mv "$temp_gemfile" Gemfile || { echo "Failed to update Gemfile" >&2; exit 1; }
}

add_gems_if_missing

bundle install || {
  echo "Bundle install failed"
```
