#!/usr/bin/env sh
set -eu
set -o pipefail

#--- Configuration -----------------------------------------------------------
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RAILS_APP_DIR=${RAILS_APP_DIR:-/home/dev/rails}
RAILS_BASE_DIR=${RAILS_BASE_DIR:-/home/dev/rails}
APP_NAME=privcam
APP_PORT=10005
SERVER_IP=185.52.176.18

#--- Logging -----------------------------------------------------------------
log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

#--- Shared functions ---------------------------------------------------------
SHARED_SCRIPT="${SCRIPT_DIR}/@shared_functions.sh"
if [ ! -f "$SHARED_SCRIPT" ]; then
    log "Shared functions not found: $SHARED_SCRIPT"
    exit 1
fi
. "$SHARED_SCRIPT"

#--- Prerequisites ------------------------------------------------------------
for cmd in rails node psql bundle; do
    command_exists "$cmd" || { log "$cmd not installed"; exit 1; }
done

#--- Database connectivity ----------------------------------------------------
if ! psql -h localhost -U postgres -l > /dev/null 2>&1; then
    log "Unable to connect to PostgreSQL"
    exit 1
fi

#--- Gem installation ---------------------------------------------------------
REQUIRED_GEMS='faker:2.23.0 pagy:8.0.2 stimulus_reflex:3.5.0'
for spec in $REQUIRED_GEMS; do
    gem_name=${spec%:*}
    gem_ver=${spec#*:}
    if ! grep -qE "gem ['\"]${gem_name}['\"][^>]*['\"]${gem_ver}['\"]" Gemfile 2>/dev/null; then
        printf "gem '%s', '%s'\n" "$gem_name" "$gem_ver" >> Gemfile
        log "Added ${gem_name} ${gem_ver} to Gemfile"
    fi
done
bundle install || { log "bundle install failed"; exit 1; }

#--- Pagy backend patch -------------------------------------------------------
APP_CTRL="${RAILS_APP_DIR}/app/controllers/application_controller.rb"
if [ -f "$APP_CTRL" ]; then
    if ! grep -q 'include Pagy::Backend' "$APP_CTRL"; then
        cp "$APP_CTRL" "${APP_CTRL}.bak"
        awk '
            /class[[:space:]]+ApplicationController/ && !found {
                print;
                print "  include Pagy::Backend";
                found=1;
                next
            }
            { print }
        ' "$APP_CTRL" > "${APP_CTRL}.tmp" && mv "${APP_CTRL}.tmp" "$APP_CTRL"
        if grep -q 'include Pagy::Backend' "$APP_CTRL"; then
            log "Patched ApplicationController with Pagy::Backend"
            rm -f "${APP_CTRL}.bak"
        else
            log "Patch failed, restoring backup"
            mv "${APP_CTRL}.bak" "$APP_CTRL"
            exit 1
        fi
    else
        log "ApplicationController already includes Pagy::Backend"
    fi
else
    log "ApplicationController not found at $APP_CTRL"
    exit 1
fi

#--- Active Storage check -----------------------------------------------------
if ! rails runner 'exit ActiveRecord::Base.connection.table_exists?("active_storage_blobs") ? 0 : 1' 2>/dev/null; then
    log "Active Storage not set up"
    exit 1
fi

#--- Scaffold generation ------------------------------------------------------
log "Generating Post scaffold..."
rails generate scaffold Post title:string content:text || { log "Scaffold generation failed"; exit 1; }

#--- Seed data ---------------------------------------------------------------
if ! rails runner 'exit Post.any? ? 0 : 1' 2>/dev/null; then
    log "Seeding database..."
    rails db:seed || { log "Database seeding failed"; exit 1; }
fi

#--- Falcon socket server -----------------------------------------------------
FALCON_PATH="/home/${APP_NAME}/app/config/falcon.rb"
if [ ! -f "$FALCON_PATH" ]; then
    cat > "$FALCON_PATH" <<'EOF'
#!/usr/bin/env ruby
# frozen_string_literal: true
require "socket"

BODY = <<~HTML.freeze
  <!DOCTYPE html>
  <html>
    <head>
      <meta charset="utf-8">
      <title>privcam</title>
      <style>
        body{font:16px/1.6 system-ui,sans-serif;max-width:700px;margin:60px auto;padding:20px}
      </style>
    </head>
    <body><h1>privcam</h1></body>
  </html>
HTML

RESP = "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{BODY.bytesize}\r\nConnection: close\r\n\r\n#{BODY}"

trap("TERM") { exit }
trap("INT")  { exit }

TCPServer.new("0.0.0.0", 10005).tap do |s|
  puts "privcam listening on 0.0.0.0:10005"
  loop do
    client = s.accept
    client.recv(4096) rescue nil
    client.print(RESP) rescue nil
    client.close rescue nil
  end
end
EOF
    chmod 755 "$FALCON_PATH"
    chown -R "${APP_NAME}:${APP_NAME}" "$(dirname "$FALCON_PATH")"
else
    log "Falcon script already exists at $FALCON_PATH"
fi

#--- RC.d service -------------------------------------------------------------
RC_SCRIPT="/etc/rc.d/${APP_NAME}_rails"
if [ ! -f "$RC_SCRIPT" ]; then
    cat > "$RC_SCRIPT" <<'EOF'
#!/bin/ksh
daemon="/usr/local/bin/ruby34"
daemon_flags="/home/privcam/app/config/falcon.rb"
daemon_user="privcam"
daemon_timeout=30

. /etc/rc.d/rc.subr

rc_bg=YES
rc_cmd "$1"
EOF
    chmod 755 "$RC_SCRIPT"
    rcctl enable "${APP_NAME}_rails" || log "Failed to enable rc service"
    rcctl start "${APP_NAME}_rails" || log "Failed to start rc service"
else
    log "RC script already exists at $RC_SCRIPT"
fi

log "Deployment completed successfully"
exit 0