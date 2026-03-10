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

validate_file_path() {
  [[ -n "$1" ]] || { echo "Error: File path is empty" >&2; return 1; }
  [[ -e "$1" ]] || { echo "Error: File does not exist: $1" >&2; return 1; }
  return 0
}

validate_pattern() {
  [[ -n "$1" ]] || { echo "Error: Pattern is empty" >&2; return 1; }
  return 0
}

install_gem() {
  local gem_name="$1"
  [[ -n "$gem_name" ]] || { echo "Error: Gem name is required" >&2; return 1; }

  if ! gem list "$gem_name gem install "$gem_name" || { echo "Error: Failed to install gem $gem_name" >&2; return 1; }
  fi
}

safe_sed_edit() {
  local file="$1"
  local pattern="$2"
  local content="$3"

  validate_file_path "$file" || return 1
  validate_pattern "$pattern" || return 1
  [[ -n "$content" ]] || { echo "Error: Content is empty" >&2; return 1; }

  if ! grep -q -- "$pattern" "$file" 2>/dev/null; then
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

  if ! command_exists bundle; then
    install_gem "bundler" || { echo "Error: Failed to install bundler" >&2; exit 1; }
  fi
}

install_dependencies() {
  [[ -f "Gemfile" ]] || { echo "Error: Gemfile not found" >&2; return 1; }

  bundle install || { echo "Error: Bundle install failed" >&2; return 1; }

  if ! grep -q "gem 'blazer'" Gemfile; then
    echo "gem 'blazer'" >> Gemfile
    bundle install || { echo "Error: Failed to install blazer" >&2; return 1; }
  fi
}
```
