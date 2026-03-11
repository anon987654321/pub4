#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${RAILS_APP_DIR:-/home/dev/rails}"
APP_NAME="privcam"
RAILS_VERSION="7.1.3"
BASE_DIR="${RAILS_BASE_DIR:-/home/dev/rails}"

SERVER_IP="185.52.176.18"
APP_PORT="3000"

# Define log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Check if shared functions file exists
SHARED_SCRIPT="${SCRIPT_DIR}/@shared_functions.sh"
if [[ ! -f "${SHARED_SCRIPT}" ]]; then
    log "Shared functions script not found: ${SHARED_SCRIPT}"
    exit 1
fi
source "${SHARED_SCRIPT}"

command_exists "rails" || { log "Rails not found"; exit 1; }
command_exists "node" || { log "Node.js not found"; exit 1; }
command_exists "psql" || { log "PostgreSQL not found"; exit 1; }

# Check database connectivity with better error handling
if ! psql -h localhost -U postgres -l > /dev/null 2>&1; then
    log "Cannot connect to PostgreSQL. Please check database configuration."
    log "Ensure PostgreSQL is running and credentials are correct."
    exit 1
fi

# Install required gems using bundle to ensure version locking
log "Installing required gems..."
if command_exists "bundle"; then
    # Add gems to Gemfile if not already present with proper version checking
    for gem_spec in "faker:2.23.0" "pagy:8.0.2" "stimulus_reflex:3.5.0"; do
        gem_name="${gem_spec%:*}"
        gem_version="${gem_spec#*:}"
        if ! grep -q "gem ['\"]${gem_name}['\"][^>]*['\"]${gem_version}['\"]" Gemfile 2>/dev/null &&
           ! grep -q "gem ['\"]${gem_name}['\"]" Gemfile 2>/dev/null; then
            echo "gem '${gem_name}', '${gem_version}'" >> Gemfile
            log "Added ${gem_name} ${gem_version} to Gemfile"
        fi
    done
    bundle install || { log "Failed to install gems via bundle"; exit 1; }
else
    log "Bundler not found, falling back to gem install"
    for gem_spec in "faker:2.23.0" "pagy:8.0.2" "stimulus_reflex:3.5.0"; do
        gem_name="${gem_spec%:*}"
        gem_version="${gem_spec#*:}"
        if ! gem list -i "${gem_name}" -v "${gem_version}" > /dev/null 2>&1; then
            gem install "${gem_name}" -v "${gem_version}" || { log "Failed to install ${gem_name}"; exit 1; }
        fi
    done
fi

# Patch ApplicationController with Pagy::Backend (idempotent)
if [[ -f "app/controllers/application_controller.rb" ]]; then
    if ! grep -q "include Pagy::Backend" "app/controllers/application_controller.rb"; then
        # Create backup and patch safely
        cp "app/controllers/application_controller.rb" "app/controllers/application_controller.rb.bak"
        sed -i '/class ApplicationController < ActionController::Base/a \  include Pagy::Backend' "app/controllers/application_controller.rb"
        if grep -q "include Pagy::Backend" "app/controllers/application_controller.rb"; then
            log "Successfully patched ApplicationController with Pagy::Backend"
            rm "app/controllers/application_controller.rb.bak"
        else
            log "Failed to patch ApplicationController, restoring backup"
            mv "app/controllers/application_controller.rb.bak" "app/controllers/application_controller.rb"
            exit 1
        fi
    else
        log "ApplicationController already includes Pagy::Backend"
    fi
else
    log "ApplicationController not found, skipping Pagy patch"
    exit 1
fi

# Improved Active Storage check with exception handling
if ! rails runner 'begin; puts ActiveRecord::Base.connection.table_exists?("active_storage_blobs"); rescue => e; puts "ERROR: #{e.message}"; exit 1; end' 2>/dev/null | grep -q "true"; then
    log "Active Storage not set up or database error occurred"
    exit 1
fi

# Enhanced scaffold generation with better error checking
log "Generating Post scaffold..."
if ! rails generate scaffold Post title:string content:text; then
    log "Failed to generate Post scaffold"
    exit 1
fi

# Improved seed check with proper error handling
if ! rails runner 'exit(Post.any? ? 0 : 1)' 2>/dev/null; then
    log "No posts found in database, running seeds..."
    if ! rails db:seed; then
        log "Failed to seed database"
        exit 1
    fi
fi

# Add proper exit codes for all error conditions
exit 0

# --- Fixed-port socket server + rc.d setup (appended) ---
APP_NAME="privcam"
APP_PORT=10005
APP_DIR="/home/${APP_NAME}/app"

# Write falcon.rb (pure Ruby stdlib socket server, no gem deps)
cat > /tmp/falcon_${APP_NAME}.rb << 'FALCONEOF'
#!/usr/bin/env ruby
# frozen_string_literal: true
require "socket"

BODY = "<!DOCTYPE html><html><head><meta charset=utf-8><title>privcam</title>" \
       "<style>body{font:16px/1.6 system-ui,sans-serif;max-width:700px;margin:60px auto;padding:20px}</style>" \
       "</head><body><h1>privcam</h1></body></html>"
RESP = "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{BODY.bytesize}\r\nConnection: close\r\n\r\n#{BODY}"

trap("TERM") { exit }
trap("INT")  { exit }

TCPServer.new("0.0.0.0", 10005).tap { |s|
  $stdout.puts "privcam on 10005"; $stdout.flush
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
daemon_flags="/home/privcam/app/config/falcon.rb"
daemon_user="privcam"
daemon_timeout=30

. /etc/rc.d/rc.subr

pexp="ruby34 /home/privcam/app/config/falcon.rb"
rc_bg=YES
rc_reload=NO

rc_cmd $1
RCDEOF

doas -u root tee /etc/rc.d/${APP_NAME}_rails < /tmp/rc_${APP_NAME} > /dev/null
doas -u root chmod 755 /etc/rc.d/${APP_NAME}_rails

# Enable and start service
doas -u root rcctl enable ${APP_NAME}_rails
doas -u root rcctl start ${APP_NAME}_rails
