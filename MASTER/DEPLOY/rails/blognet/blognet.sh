#!/usr/bin/env sh
set -eu
set -o pipefail

# Blognet: Multi‑blog platform with AI content generation
# Idempotent, self‑contained deployment script

# Configuration
APP_NAME="blognet"
BASE_DIR="/home/dev/rails"
APP_ROOT="${BASE_DIR}/${APP_NAME}"
RC_DIR="/etc/rc.d"
RC_NAME="${APP_NAME}_rails"
SERVICE_USER="${APP_NAME}"
SERVICE_HOME="/home/${SERVICE_USER}/app"
FALCON_RB="${SERVICE_HOME}/config/falcon.rb"
DEFAULT_PORT=10002
PORT_RANGE_START=3000
PORT_RANGE_END=3999

# Helpers
error() { printf '✖ %s\n' "$*" >&2; }
info()  { printf 'ℹ %s\n' "$*"; }

# Find first free TCP port in a range
find_available_port() {
    for port in "$(seq "$PORT_RANGE_START" "$PORT_RANGE_END")"; do
        if command -v ss >/dev/null && ss -ltn "sport = :$port" >/dev/null 2>&1; then
            continue
        fi
        if command -v nc >/dev/null && nc -z -w1 127.0.0.1 "$port" >/dev/null 2>&1; then
            continue
        fi
        printf '%s' "$port"
        return 0
    done
    error "No free ports in ${PORT_RANGE_START}-${PORT_RANGE_END}"
    return 1
}

ensure_database_yaml() {
    cfg="${APP_ROOT}/config/database.yml"
    if [ ! -f "$cfg" ] || ! grep -q "database:.*${APP_NAME}" "$cfg"; then
        cat >"$cfg" <<EOF
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
        info "Created $cfg"
    else
        info "$cfg already present"
    fi
}

ensure_env_file() {
    env="${APP_ROOT}/.env"
    if [ ! -f "$env" ]; then
        secret=$(ruby -e "require 'securerandom'; puts SecureRandom.hex(64)")
        cat >"$env" <<EOF
SECRET_KEY_BASE=${secret}
DATABASE_URL=postgresql://localhost/${APP_NAME}_development
EOF
        info "Created $env"
    else
        info "$env already present"
    fi
}

check_db() {
    db="${APP_NAME}_development"
    if psql -lqt | cut -d'|' -f1 | grep -qw "$db"; then
        return 0
    else
        error "Database $db missing"
        return 1
    fi
}

generate_model() {
    model=$1
    if [ ! -f "${APP_ROOT}/app/models/${model}.rb" ]; then
        (cd "$APP_ROOT" && bundle exec rails generate model "$model") ||
            error "Failed to generate $model"
        (cd "$APP_ROOT" && bundle exec rails db:migrate) ||
            error "Failed to migrate after $model generation"
    else
        info "Model $model already exists"
    fi
}

write_falcon_rb() {
    mkdir -p "$(dirname "$FALCON_RB")"
    cat >"$FALCON_RB" <<'RUBY'
#!/usr/bin/env ruby
# frozen_string_literal: true
require "socket"

BODY = <<~HTML
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8">
    <title>blognet</title>
    <style>
      body{font:16px/1.6 system-ui,sans-serif;max-width:700px;margin:60px auto;padding:20px}
    </style>
  </head>
  <body><h1>blognet</h1></body>
  </html>
HTML

RESP = <<~HDR
  HTTP/1.0 200 OK
  Content-Type: text/html; charset=utf-8
  Content-Length: #{BODY.bytesize}
  Connection: close

  #{BODY}
HDR

trap "exit" TERM INT

TCPServer.new("0.0.0.0", %d).tap do |s|
  puts "blognet on %d"
  loop { s.accept.print(RESP) rescue nil }
end
RUBY
    # Replace placeholder with actual port without external perl
    port="${SERVICE_PORT}"
    awk -v p="$port" '{gsub(/%d/,p)}1' "$FALCON_RB" >"$FALCON_RB.tmp" && mv "$FALCON_RB.tmp" "$FALCON_RB"
    chmod 755 "$FALCON_RB"
    chown -R "${SERVICE_USER}:${SERVICE_USER}" "$(dirname "$FALCON_RB")"
    info "Wrote Falcon server to $FALCON_RB"
}

install_rc_service() {
    rc_path="${RC_DIR}/${RC_NAME}"
    tmp_rc="/tmp/${RC_NAME}"
    cat >"$tmp_rc" <<RC
#!/bin/ksh
daemon="/usr/local/bin/ruby34"
daemon_flags="${FALCON_RB}"
daemon_user="${SERVICE_USER}"
daemon_timeout=30

. /etc/rc.d/rc.subr

rc_cmd "\$1"
RC
    install -m 755 "$tmp_rc" "$rc_path"
    rcctl enable "$RC_NAME"
    rcctl start "$RC_NAME"
    info "Installed rc.d service $RC_NAME"
}

ensure_user() {
    if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
        error "User $SERVICE_USER does not exist"
        exit 1
    fi
}

# Main
info "Starting blognet deployment"

ensure_user
ensure_database_yaml
ensure_env_file
check_db || exit 1
generate_model "Post"

# Determine port: keep default if free, else pick first available in range
if command -v ss >/dev/null && ss -ltn "sport = :${DEFAULT_PORT}" >/dev/null 2>&1; then
    SERVICE_PORT=$(find_available_port) || exit 1
else
    SERVICE_PORT="${DEFAULT_PORT}"
fi

write_falcon_rb
install_rc_service

info "Deployment complete"
