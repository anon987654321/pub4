```zsh
#!/usr/bin/env zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Hjerterom - Mental health and food redistribution platform

readonly APP_NAME="hjerterom"
readonly BASE_DIR="${BASE_DIR:-${HOME}/rails}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source shared functions if available
SHARED_FUNCTIONS="${SCRIPT_DIR}/@shared_functions.sh"
[[ -f "$SHARED_FUNCTIONS" ]] && source "$SHARED_FUNCTIONS"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_gem() {
  local gem_name="$1"
  if ! gem list | grep -q "$gem_name"; then
    gem install "$gem_name" || { echo "Error: Failed to install gem $gem_name" >&2; exit 1; }
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
    echo "$content" >> "$file" || { echo "Error: Failed to write to $file" >&2; return 1; }
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
    echo "Please install them before running this script" >&2
    exit 1
  fi

  if ! command_exists "rails" && [[ ! -f "bin/rails" ]]; then
    echo "Error: Rails not found. Please ensure you're in a Rails application directory." >&2
    exit 1
  fi

  if [[ ! -f "Gemfile" ]]; then
    echo "Error: Not in a Rails application directory (Gemfile not found)" >&2
    exit 1
  fi
}

install_dependencies() {
  if ! grep -q "faker" Gemfile; then
    install_gem "faker" || return 1
  fi
  if ! grep -q "omniauth-vipps" Gemfile; then
    install_gem "omniauth-vipps" || return 1
  fi
  if ! grep -q "ahoy_matey" Gemfile; then
    install_gem "ahoy_matey" || return 1
  fi
  if ! grep -q "blazer" Gemfile; then
    install_gem "blazer" || return 1
  fi
  if ! grep -q "chartkick" Gemfile; then
    install_gem "chartkick" || return 1
  fi
}

write_ahoy_initializer() {
  local initializer_file="config/initializers/ahoy.rb"
  if [[ ! -f "$initializer_file" ]]; then
    cat > "$initializer_file" << 'EOF'
Ahoy.api = true
Ahoy.visit_duration = 30.minutes
EOF
    echo "Created Ahoy initializer"
  fi
}

write_blazer_initializer() {
  local initializer_file="config/initializers/blazer.rb"
  if [[ ! -f "$initializer_file" ]]; then
    cat > "$initializer_file" << 'EOF'
Blazer.time_zone = "Oslo"
Blazer.audit = true
EOF
    echo "Created Blazer initializer"
  fi
}

generate_models() {
  [[ -f "bin/rails" ]] || { echo "Error: Not in Rails application directory" >&2; exit 1; }
  [[ -f "Gemfile" ]] || { echo "Error: Not in Rails application directory" >&2; exit 1; }

  bin/rails generate model Distribution name:string description:text status:string user:references || { echo "Error: Failed to generate Distribution model" >&2; exit 1; }
}
```
