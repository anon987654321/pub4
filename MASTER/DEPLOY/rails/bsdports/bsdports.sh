#!/usr/bin/env sh
set -eu
set -o pipefail

#--- Configuration ------------------------------------------------------------
APP_NAME="bsdports"
BASE_DIR="${BASE_DIR:-/home/dev/rails}"
SERVER_IP="${SERVER_IP:-185.52.176.18}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export RAILS_ENV="${RAILS_ENV:-production}"

#--- Shared utilities ---------------------------------------------------------
. "${SCRIPT_DIR}/@shared_functions.sh" || {
    printf 'Error: cannot source %s\n' "${SCRIPT_DIR}/@shared_functions.sh" >&2
    exit 1
}

# Ensure required helper exists
command -v validate_port_available >/dev/null 2>&1 || {
    printf 'Error: validate_port_available function not found\n' >&2
    exit 1
}

#--- Port selection -----------------------------------------------------------
# POSIX‑compatible random port selection
RANDOM="$(dd if=/dev/urandom bs=4 count=1 2>/dev/null | od -An -tu4 | tr -d ' ')"
MAX_RETRIES=10
retry=0
while :; do
    candidate_port=$((10000 + RANDOM % 55536))
    [ "$candidate_port" -le 65535 ] || candidate_port=65535
    if validate_port_available "$candidate_port"; then
        APP_PORT=$candidate_port
        printf 'Selected port: %s\n' "$APP_PORT"
        break
    fi
    retry=$((retry + 1))
    if [ "$retry" -ge "$MAX_RETRIES" ]; then
        printf 'Error: unable to find free port after %s attempts\n' "$MAX_RETRIES" >&2
        exit 1
    fi
done

#--- Database checks -----------------------------------------------------------
if ! bin/rails db:version >/dev/null 2>&1; then
    printf 'Error: invalid database configuration or unreachable DB\n' >&2
    exit 1
fi

if ! bin/rails db:migrate; then
    printf 'Error: Rails migration failed\n' >&2
    exit 1
fi

#--- Falcon socket server -----------------------------------------------------
FALCON_RB="$(mktemp -u /tmp/falcon_${APP_NAME}.rb.XXXXXX)"
cat >"$FALCON_RB" <<'EOF'
#!/usr/bin/env ruby
# frozen_string_literal: true
require 'socket'

BODY = <<~HTML
  <!DOCTYPE html><html><head><meta charset=utf-8><title>bsdports</title>
  <style>body{font:16px/1.6 system-ui,sans-serif;max-width:700px;margin:60px auto;padding:20px}</style>
  </head><body><h1>bsdports</h1></body></html>
HTML

RESP = <<~HTTP
  HTTP/1.0 200 OK
  Content-Type: text/html; charset=utf-8
  Content-Length: #{BODY.bytesize}
  Connection: close

  #{BODY}
HTTP

trap('TERM') { exit }
trap('INT')  { exit }

TCPServer.new('0.0.0.0', ENV.fetch('APP_PORT', '10003')).tap do |s|
  puts "bsdports on #{s.addr[1]}"
  loop do
    client = s.accept
    client.recv(4096) rescue nil
    client.print(RESP) rescue nil
    client.close rescue nil
  end
end
EOF
chmod +x "$FALCON_RB"

APP_DIR="/home/${APP_NAME}/app"
CONFIG_DIR="${APP_DIR}/config"

doas -u root mkdir -p "$CONFIG_DIR"
doas -u root cp "$FALCON_RB" "${CONFIG_DIR}/falcon.rb"
doas -u root chown "${APP_NAME}:${APP_NAME}" "${CONFIG_DIR}/falcon.rb"
rm -f "$FALCON_RB"

#--- rc.d service -------------------------------------------------------------
RC_SCRIPT="$(mktemp -u /tmp/rc_${APP_NAME}.XXXXXX)"
cat >"$RC_SCRIPT" <<EOS
#!/bin/ksh
. /etc/rc.d/rc.subr

name="${APP_NAME}_rails"
rcvar=\${name}
command="/usr/local/bin/ruby34"
command_args="${CONFIG_DIR}/falcon.rb"
rc_flags="\${command_args}"
rc_need="network"
rc_bg=YES
rc_reload=NO

run_rc_command "\$1"
EOS
chmod 755 "$RC_SCRIPT"
doas -u root cp "$RC_SCRIPT" "/etc/rc.d/${APP_NAME}_rails"
rm -f "$RC_SCRIPT"

doas -u root rcctl enable "${APP_NAME}_rails"
doas -u root rcctl start "${APP_NAME}_rails"