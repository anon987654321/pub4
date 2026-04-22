#!/usr/bin/env sh
set -euo pipefail

# hjerterom – mental‑health & food redistribution platform
# -------------------------------------------------------
# Idempotent deployment of a minimal Falcon HTTP server as an rc.d service
# on OpenBSD.  Re‑run safely; existing files are left untouched and the
# service is (re)started only when needed.

readonly APP_NAME="hjerterom"
readonly APP_DIR="/home/${APP_NAME}/app"
readonly CONFIG_DIR="${APP_DIR}/config"
readonly FALCON_SCRIPT="${CONFIG_DIR}/falcon.rb"
readonly RC_SCRIPT="/etc/rc.d/${APP_NAME}_rails"
readonly RC_USER="${APP_NAME}"
readonly APP_PORT=10004

# -------------------------------------------------------
# Helpers
# -------------------------------------------------------
command_exists() { command -v "$1" >/dev/null 2>&1; }

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_commands() {
  missing=
  for cmd in ruby rcctl; do
    command_exists "$cmd" || missing="${missing}${cmd} "
  done
  [ -z "$missing" ] || die "Missing commands: $missing"
}

install_falcon_server() {
  # Write the server only if missing or checksum differs
  if [ -f "$FALCON_SCRIPT" ]; then
    # compare inline to avoid rewriting unchanged file
    tmp=$(mktemp)
    cat >"$tmp" <<'EOF'
#!/usr/bin/env ruby
# frozen_string_literal: true
require "socket"

BODY = "<!DOCTYPE html><html><head><meta charset=utf-8><title>hjernerom</title>" \
       "<style>body{font:16px/1.6 system-ui,sans-serif;max-width:700px;margin:60px auto;padding:20px}</style>" \
       "</head><body><h1>hjernerom</h1></body></html>"
RESP = "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{BODY.bytesize}\r\nConnection: close\r\n\r\n#{BODY}"

trap("TERM") { exit }
trap("INT")  { exit }

TCPServer.new("0.0.0.0", ${APP_PORT}).tap do |s|
  $stdout.puts "hjernerom on ${APP_PORT}"
  loop { c = s.accept; c.recv(4096) rescue nil; c.print(RESP) rescue nil; c.close rescue nil }
end
EOF
    if ! cmp -s "$tmp" "$FALCON_SCRIPT"; then
      cp "$tmp" "$FALCON_SCRIPT"
      chmod +x "$FALCON_SCRIPT"
    fi
    rm -f "$tmp"
  else
    mkdir -p "$CONFIG_DIR"
    install_falcon_server # recursive call creates the file
  fi
}

install_rc_service() {
  # Create rc.d script only if missing or changed
  tmp=$(mktemp)
  cat >"$tmp" <<EOF
#!/bin/ksh
daemon="/usr/local/bin/ruby34"
daemon_flags="${FALCON_SCRIPT}"
daemon_user="${RC_USER}"
daemon_timeout=30

. /etc/rc.d/rc.subr

rc_bg=YES
rc_reload=NO

rc_cmd "\$1"
EOF

  if [ ! -f "$RC_SCRIPT" ] || ! cmp -s "$tmp" "$RC_SCRIPT"; then
    cp "$tmp" "$RC_SCRIPT"
    chmod 755 "$RC_SCRIPT"
    rcctl enable "${APP_NAME}_rails"
  fi
  rm -f "$tmp"
}

start_service() {
  rcctl start "${APP_NAME}_rails" || die "Failed to start ${APP_NAME}_rails"
}

# -------------------------------------------------------
# Main
# -------------------------------------------------------
require_commands
install_falcon_server
install_rc_service
start_service

printf 'Deployment of %s completed successfully.\n' "$APP_NAME"
