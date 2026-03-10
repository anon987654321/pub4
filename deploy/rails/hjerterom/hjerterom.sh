```zsh
#!/usr/bin/env zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Hjerterom - Mental health and food redistribution platform

readonly APP_NAME="hjerterom"
readonly BASE_DIR="${BASE_DIR:-/home/dev/rails}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SERVER_IP="185.52.176.18"
readonly APP_PORT=$((10000 + RANDOM % 10000))

# Source shared functions if available
SHARED_FUNCTIONS="${SCRIPT_DIR}/@shared_functions.sh"
[[ -f "$SHARED_FUNCTIONS" ]] && source "$SHARED_FUNCTIONS"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_gem() {
  local gem_name="$1"
  if ! gem list | grep -q "$gem_name"; then
    gem install "$gem_name"
  fi
}

safe_sed_edit() {
  local file="$1"
  local pattern="$2"
  local content="$3"

  if [[ ! -f "$file" ]]; then
    echo "Warning: File $file does not exist" >&2
    return 1
  fi

  if ! grep -q "$pattern" "$file" 2>/dev/null; then
    echo "$content" >> "$file"
  fi
}

setup_environment() {
  local missing_commands=()

  for cmd in ruby node psql; do
    if ! command_exists "$cmd"; then
      missing_commands+=("$cmd")
    fi
  done

  if [[ ${#missing_commands[@]} -gt 0 ]]; then
    echo "Error: Missing required commands: ${missing_commands[*]}" >&2
    exit 1
  fi

  if ! command_exists "rails" && [[ ! -f "bin/rails" ]]; then
    echo "Error: Rails not found. Please ensure you're in a Rails application directory." >&2
    exit 1
  fi
}

install_dependencies() {
  install_gem "faker"
  install_gem "omniauth-vipps"
  install_gem "ahoy_matey"
  install_gem "blazer"
  install_gem "chartkick"

  safe_sed_edit "app/controllers/application_controller.rb" \
    "Pagy::Backend" \
    "class ApplicationController < ActionController::Base\n  include Pagy::Backend"

  safe_sed_edit "app/helpers/application_helper.rb" \
    "Pagy::Frontend" \
    "module ApplicationHelper\n  include Pagy::Frontend"
}

generate_models() {
  [[ -f "bin/rails" ]] || { echo "Error: Not in Rails application directory"; return 1; }

  bin/rails generate model Distribution \
    location:string schedule:datetime capacity:integer \
    lat:decimal lng:decimal
  bin/rails generate model Giveaway \
    title:string description:text quantity:integer \
    pickup_time:datetime location:string lat:decimal lng:decimal \
    user:references status:string anonymous:boolean
  bin/rails generate migration AddVippsToUsers \
    vipps_id:string citizenship_status:string claim_count:integer
}

setup_initializers() {
  write_ahoy_initializer
  write_blazer_initializer
}

generate_controllers() {
  [[ -f "bin/rails" ]] || { echo "Error: Not in Rails application directory"; return 1; }

  write_application_controller
  write_home_controller
  write_distributions_controller
  write_giveaways_controller
}

# Removed unused guest_user_allowed? function
```
