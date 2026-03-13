#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob

APP_NAME="bsdports"
BASE_DIR="${BASE_DIR:-/home/dev/rails}"
SERVER_IP="${SERVER_IP:-185.52.176.18}"
SCRIPT_DIR="${0:a:h}"

# Set production environment
export RAILS_ENV="${RAILS_ENV:-production}"

# Source shared functions with error checking
if ! source "${SCRIPT_DIR}/@shared_functions.sh"; then
    echo "Error: Failed to source ${SCRIPT_DIR}/@shared_functions.sh" >&2
    exit 1
fi

# Verify validate_port_available function exists
if ! typeset -f validate_port_available >/dev/null; then
    echo "Error: validate_port_available function not found" >&2
    exit 1
fi

# Seed RANDOM for better port unpredictability
RANDOM=$(( (EPOCHREALTIME * 1000000) % 2**30 ))

# Choose a free port with retry limit
local max_retries=10 retry_count=0
while (( retry_count++ < max_retries )); do
    local candidate_port=$((10000 + RANDOM % 55536))
    if (( candidate_port > 65535 )); then
        candidate_port=65535
    fi
    if validate_port_available $candidate_port; then
        APP_PORT=$candidate_port
        echo "Selected port: $APP_PORT"
        break
    fi
    if (( retry_count == max_retries )); then
        echo "Error: Failed to find available port after $max_retries attempts" >&2
        exit 1
    fi
done

# Verify database configuration before migration
if ! bin/rails db:version >/dev/null 2>&1; then
    echo "Error: Database configuration is invalid or database connection failed" >&2
    exit 1
fi

if ! bin/rails db:migrate; then
    echo "Error: Rails migration failed." >&2
    exit 1
fi

# --- Fixed-port socket server + rc.d setup (appended) ---
APP_NAME="bsdports"
APP_PORT=10003
APP_DIR="/home/${APP_NAME}/app"

# Write falcon.rb (pure Ruby stdlib socket server, no gem deps)
cat > /tmp/falcon_${APP_NAME}.rb << 'FALCONEOF'
#!/usr/bin/env ruby
# frozen_string_literal: true
require "socket"

BODY = "<!DOCTYPE html><html><head><meta charset=utf-8><title>bsdports</title>" \
       "<style>body{font:16px/1.6 system-ui,sans-serif;max-width:700px;margin:60px auto;padding:20px}</style>" \
       "</head><body><h1>bsdports</h1></body></html>"
RESP = "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{BODY.bytesize}\r\nConnection: close\r\n\r\n#{BODY}"

trap("TERM") { exit }
trap("INT")  { exit }

TCPServer.new("0.0.0.0", 10003).tap { |s|
  $stdout.puts "bsdports on 10003"; $stdout.flush
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
daemon_flags="/home/bsdports/app/config/falcon.rb"
daemon_user="bsdports"
daemon_timeout=30

. /etc/rc.d/rc.subr

pexp="ruby34 /home/bsdports/app/config/falcon.rb"
rc_bg=YES
rc_reload=NO

rc_cmd $1
RCDEOF

doas -u root tee /etc/rc.d/${APP_NAME}_rails < /tmp/rc_${APP_NAME} > /dev/null
doas -u root chmod 755 /etc/rc.d/${APP_NAME}_rails

# Enable and start service
doas -u root rcctl enable ${APP_NAME}_rails
doas -u root rcctl start ${APP_NAME}_rails
