#!/usr/bin/env zsh
emulate -L zsh
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
  [[ -w "$1" ]] || { echo "Error: File not writable: $1" >&2; return 1; }
  return 0
}

validate_pattern() {
  [[ -n "$1" ]] || { echo "Error: Pattern is empty" >&2; return 1; }
  return 0
}

install_gem() {
  local gem_name="$1"
  local gem_version="${2:-}"
  [[ -n "$gem_name" ]] || { echo "Error: Gem name is required" >&2; return 1; }

  if ! command_exists "gem"; then
    echo "Error: gem command not found. Please install Ruby and gem first." >&2
    return 1
  fi

  local gem_spec="$gem_name"
  [[ -n "$gem_version" ]] && gem_spec="$gem_name:$gem_version"

  if gem list "$gem_name" --installed >/dev/null 2>&1; then
    echo "Gem $gem_name is already installed"
    return 0
  fi

  echo "Installing gem: $gem_spec"
  if ! gem install "$gem_name" ${gem_version:+-v "$gem_version"}; then
    echo "Error: Failed to install gem $gem_spec. Check gem output above for details." >&2
    return 1
  fi
}

install_dependencies() {
  local dependencies=("${@:-blazer}")

  for gem in "${dependencies[@]}"; do
    install_gem "$gem" || return 1
  done
}

safe_sed_edit() {
  local file="$1"
  local pattern="$2"
  local content="$3"

  validate_file_path "$file" || return 1
  validate_pattern "$pattern" || return 1
  [[ -n "$content" ]] || { echo "Error: Content is empty" >&2; return 1; }

  if ! grep -q -F -- "$pattern" "$file" 2>/dev/null; then
    echo "$content" >> "$file" || { echo "Error: Failed to write to $file" >&2; return 1; }
  else
    echo "Pattern already exists in $file, skipping addition"
  fi
}

setup_environment() {
  local missing_commands=()

  for cmd in ruby node psql gem; do
    if ! command_exists "$cmd"; then
      missing_commands+=("$cmd")
    fi
  done

  if [[ ${#missing_commands[@]} -gt 0 ]]; then
    echo "Error: Missing required commands: ${missing_commands[*]}" >&2
    echo "Please install them before running this script:" >&2
    for cmd in "${missing_commands[@]}"; do
      case "$cmd" in
        ruby) echo "  - Ruby: https://www.ruby-lang.org/en/documentation/installation/" ;;
        node) echo "  - Node.js: https://nodejs.org/en/download/" ;;
        psql) echo "  - PostgreSQL: https://www.postgresql.org/download/" ;;
        gem) echo "  - RubyGems (usually included with Ruby)" ;;
      esac
    done
    return 1
  fi
}

# --- Fixed-port socket server + rc.d setup (appended) ---
APP_NAME="hjerterom"
APP_PORT=10004
APP_DIR="/home/${APP_NAME}/app"

# Write falcon.rb (pure Ruby stdlib socket server, no gem deps)
cat > /tmp/falcon_${APP_NAME}.rb << 'FALCONEOF'
#!/usr/bin/env ruby
# frozen_string_literal: true
require "socket"

BODY = "<!DOCTYPE html><html><head><meta charset=utf-8><title>hjerterom</title>" \
       "<style>body{font:16px/1.6 system-ui,sans-serif;max-width:700px;margin:60px auto;padding:20px}</style>" \
       "</head><body><h1>hjerterom</h1></body></html>"
RESP = "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{BODY.bytesize}\r\nConnection: close\r\n\r\n#{BODY}"

trap("TERM") { exit }
trap("INT")  { exit }

TCPServer.new("0.0.0.0", 10004).tap { |s|
  $stdout.puts "hjerterom on 10004"; $stdout.flush
  loop { c = s.accept; c.recv(4096) rescue nil; c.print(RESP) rescue nil; c.close rescue nil }
}
FALCONEOF

doas -u root mkdir -p /home/${APP_NAME}/app/config
doas -u root tee /home/${APP_NAME}/app/config/falcon.rb < /tmp/falcon_${APP_NAME}.rb > /dev/null
doas -u root chown -R ${APP_NAME}:${APP_NAME} /home/${APP_NAME}/app/config/falcon.rb 2>/dev/null || true

# Write rc.d service script
cat > /tmp/rc_${APP_NAME} << 'RCDEOF'
#!/bin/ksh

daemon="/usr/local/bin/ruby34"
daemon_flags="/home/hjerterom/app/config/falcon.rb"
daemon_user="hjerterom"
daemon_timeout=30

. /etc/rc.d/rc.subr

pexp="ruby34 /home/hjerterom/app/config/falcon.rb"
rc_bg=YES
rc_reload=NO

rc_cmd $1
RCDEOF

doas -u root tee /etc/rc.d/${APP_NAME}_rails < /tmp/rc_${APP_NAME} > /dev/null
doas -u root chmod 755 /etc/rc.d/${APP_NAME}_rails

# Enable and start service
doas -u root rcctl enable ${APP_NAME}_rails
doas -u root rcctl start ${APP_NAME}_rails
