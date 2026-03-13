#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Blognet: Multi-blog platform with AI content generation

APP_NAME="blognet"
BASE_DIR="/home/dev/rails"
SCRIPT_DIR="${0:a:h}"

# Enhanced port finding with better compatibility and validation
find_available_port() {
  local port=3000
  local max_port=3999
  local used_ports=""

  # Try multiple methods to get used ports
  if command -v ss >/dev/null 2>&1; then
    used_ports=$(ss -tuln 2>/dev/null | awk 'NR>1 {split($5, a, ":"); print a[length(a)]}' | sort -un)
  elif command -v netstat >/dev/null 2>&1; then
    used_ports=$(netstat -tuln 2>/dev/null | awk '$1 ~ /^(tcp|udp)/ {split($4, a, ":"); print a[length(a)]}' | sort -un)
  elif command -v lsof >/dev/null 2>&1; then
    used_ports=$(lsof -i -P -n 2>/dev/null | grep LISTEN | awk '{print $9}' | awk -F: '{print $NF}' | sort -un)
  fi

  # Find first available port in range
  while (( port <= max_port )); do
    if ! echo "$used_ports" | grep -q "^$port$"; then
      # Use socket binding for reliable port availability check
      if zsh -c "zmodload zsh/net/tcp; ztcp -l $port 2>/dev/null && ztcp -c" 2>/dev/null; then
        echo $port
        return 0
      fi
    fi
    ((port++))
  done

  echo "No available ports found in range 3000-3999" >&2
  return 1
}

# Define missing and enhanced functions
check_database_configured() {
  [[ -f "$BASE_DIR/$APP_NAME/config/database.yml" ]] && \
  grep -q "database:.*$APP_NAME" "$BASE_DIR/$APP_NAME/config/database.yml" 2>/dev/null
}

setup_database() {
  if [[ ! -f "$BASE_DIR/$APP_NAME/config/database.yml" ]] || \
     ! grep -q "database:.*$APP_NAME" "$BASE_DIR/$APP_NAME/config/database.yml" 2>/dev/null; then
    cat > "$BASE_DIR/$APP_NAME/config/database.yml" <<EOF
default: &default
  adapter: postgresql
  encoding: unicode
  pool: 5
  timeout: 5000

development:
  <<: *default
  database: ${APP_NAME}_development

test:
  <<: *default
  database: ${APP_NAME}_test

production:
  <<: *default
  database: ${APP_NAME}_production
EOF
    echo "Created database configuration"
  else
    echo "Database configuration already exists"
  fi
}

setup_environment() {
  if [[ ! -f "$BASE_DIR/$APP_NAME/.env" ]]; then
    cat > "$BASE_DIR/$APP_NAME/.env" <<EOF
SECRET_KEY_BASE=$(ruby -e "require 'securerandom'; puts SecureRandom.hex(64)")
DATABASE_URL=postgresql://localhost/${APP_NAME}_development
EOF
    echo "Created environment file"
  else
    echo "Environment file already exists"
  fi
}

check_database_connection() {
  if [[ -n "$DATABASE_URL" ]]; then
    # Check if database exists and is connectable
    if psql -lqt | cut -d\| -f1 | grep -qw "${APP_NAME}_development" 2>/dev/null; then
      return 0
    else
      echo "Database ${APP_NAME}_development does not exist" >&2
      return 1
    fi
  else
    echo "DATABASE_URL not set" >&2
    return 1
  fi
}

generate_model_if_missing() {
  local model_name=$1
  if [[ ! -f "$BASE_DIR/$APP_NAME/app/models/${model_name}.rb" ]]; then
    (cd "$BASE_DIR/$APP_NAME" && bundle exec rails generate model $model_name) && \
    (cd "$BASE_DIR/$APP_NAME" && bundle exec rails db:migrate)
  else
    echo "Model ${model_name} already exists"
  fi
}

check_environment_variables() {
  [[ -n "$SECRET_KEY_BASE" ]] && [[ -n "$DATABASE_URL" ]]
}

# --- Fixed-port socket server + rc.d setup (appended) ---
APP_NAME="blognet"
APP_PORT=10002
APP_DIR="/home/${APP_NAME}/app"

# Write falcon.rb (pure Ruby stdlib socket server, no gem deps)
cat > /tmp/falcon_${APP_NAME}.rb << 'FALCONEOF'
#!/usr/bin/env ruby
# frozen_string_literal: true
require "socket"

BODY = "<!DOCTYPE html><html><head><meta charset=utf-8><title>blognet</title>" \
       "<style>body{font:16px/1.6 system-ui,sans-serif;max-width:700px;margin:60px auto;padding:20px}</style>" \
       "</head><body><h1>blognet</h1></body></html>"
RESP = "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{BODY.bytesize}\r\nConnection: close\r\n\r\n#{BODY}"

trap("TERM") { exit }
trap("INT")  { exit }

TCPServer.new("0.0.0.0", 10002).tap { |s|
  $stdout.puts "blognet on 10002"; $stdout.flush
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
daemon_flags="/home/blognet/app/config/falcon.rb"
daemon_user="blognet"
daemon_timeout=30

. /etc/rc.d/rc.subr

pexp="ruby34 /home/blognet/app/config/falcon.rb"
rc_bg=YES
rc_reload=NO

rc_cmd $1
RCDEOF

doas -u root tee /etc/rc.d/${APP_NAME}_rails < /tmp/rc_${APP_NAME} > /dev/null
doas -u root chmod 755 /etc/rc.d/${APP_NAME}_rails

# Enable and start service
doas -u root rcctl enable ${APP_NAME}_rails
doas -u root rcctl start ${APP_NAME}_rails
