#!/usr/bin/env zsh
# @server.sh — sourced via @shared_functions.sh
set -euo pipefail


install_rcd() {
  local svc=$1 app_dir=$2 port=$3 user=$4
  local rcd="/etc/rc.d/${svc}"
  [[ -f $rcd ]] && { log_ok "rc.d/${svc} already exists"; return 0; }
  local secret
  secret=$(ruby34 -e 'require "securerandom"; print SecureRandom.hex(64)')
  $_PRIV tee "$rcd" > /dev/null << EOS
#!/bin/ksh
daemon="/usr/local/bin/bundle"
daemon_flags="exec env RAILS_ENV=production SECRET_KEY_BASE=${secret} HOME=/home/${user} falcon serve --bind http://127.0.0.1:${port}"
daemon_user="${user}"
daemon_execdir="${app_dir}"
daemon_timeout="60"
. /etc/rc.d/rc.subr
pexp="ruby.*${port}"
rc_bg=YES
rc_reload=NO
rc_cmd \$1
EOS
  $_PRIV chmod 755 "$rcd"
  $_PRIV rcctl enable "$svc"
  # App must be owned by the service user so it can write storage/log/tmp
  $_PRIV chown -R "${user}:${user}" "${app_dir}"
  log_ok "rc.d/${svc} installed (falcon on :${port})"
}

relayd_add_relay() {
  local host=$1 port=$2
  local table="${host%%.*}"
  local conf=/etc/relayd.conf
  grep -q "table <${table}>" "$conf" 2>/dev/null && { log_ok "relayd <${table}> exists"; return 0; }
  $_PRIV tee -a "$conf" > /dev/null << EOS

table <${table}> { 127.0.0.1 }
relay "${table}_http" {
  listen on 0.0.0.0 port 80
  forward to <${table}> port ${port} check tcp
}
EOS
  log_ok "relayd table <${table}> -> :${port} added"
}

write_falcon_config() {
  local port=${1:-3000}
  add_gem falcon
  cat > config/falcon.rb << FALCON
#!/usr/bin/env -S falcon host
# frozen_string_literal: true

load :rack, :supervisor

hostname = File.basename(__dir__)
port = ENV.fetch("PORT", ${port}).to_i

rack hostname do
  endpoint Async::HTTP::Endpoint.parse("http://0.0.0.0:\#{port}")
end
FALCON
  log_ok "Falcon config written (:${port})"
}

install_thruster() {
  add_gem thruster
  log_ok "Thruster added"
}
