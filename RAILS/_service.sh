#!/usr/bin/env zsh
# _service.sh — rc.d service installation and relayd routing for copy-tree deploy.
# Source this file; do not execute directly. Requires _core.sh sourced first.

# retire_legacy_rails_rcd APP_NAME — stop duplicate *_rails services from older bootstrap.
retire_legacy_rails_rcd() {
  local app_name=$1 legacy="${app_name}_rails"
  [[ -f /etc/rc.d/$legacy ]] || return 0
  ${_PRIV} rcctl disable "$legacy" 2>/dev/null || true
  log_ok "disabled legacy rc.d ${legacy} (no stop — shared port with ${app_name})"
}

# assert_rcd_identity — CY15: rc.d daemon_user and APP_DIR must match deploy target.
assert_rcd_identity() {
  local svc=$1 expected_user=$2 expected_dir=$3
  local rcd="/etc/rc.d/${svc}"
  [[ -f $rcd ]] || return 0
  local body; body=$(<"$rcd")
  [[ $body == *"daemon_user=\"${expected_user}\""* ]] || {
    log_err "rc.d ${svc}: daemon_user must be ${expected_user}"
    return 1
  }
  [[ $body == *"daemon_execdir=\"${expected_dir}\""* ]] || {
    log_err "rc.d ${svc}: daemon_execdir must be ${expected_dir}"
    return 1
  }
  log_ok "rc.d ${svc} identity ok (${expected_user} → ${expected_dir})"
}

# install_rcd APP_NAME APP_DIR PORT SERVICE_NAME
# Installs or updates the rc.d service file for a Rails app on OpenBSD.
install_rcd() {
  local app_name=$1 app_dir=$2 port=$3 svc=${4:-$1}
  local openbsd_root=${PUB4_OPENBSD_ROOT:-/home/dev/pub4/OPENBSD}
  local rcd_src="${openbsd_root}/etc/rc.d/${svc}"
  local rcd_dst="/etc/rc.d/${svc}"
  if [[ ! -f $rcd_src ]]; then
    log_warn "rc.d template not found: $rcd_src — skipping install_rcd"
    return 0
  fi
  ${_PRIV} install -o root -g wheel -m 0555 "$rcd_src" "$rcd_dst"
  assert_rcd_identity "$svc" "$app_name" "$app_dir"
  retire_legacy_rails_rcd "$app_name"
  ${_PRIV} rcctl enable "$svc"
  log_ok "rc.d ${svc} installed and enabled"
}

# relayd_confirm_live PORT
# Post-restart verification, deliberately separate from the pre-restart config
# validation above it.
#
# `rcctl restart relayd` returns 0 when the start command succeeded, and that is
# not the same claim as "relayd is serving". On 2026-08-10 the ca process died
# during a restart (ca_dispatch_relay: invalid relay hash -> lost child ->
# parent terminating) and took every site on the box down for nine minutes; the
# deploy that triggered it had logged relayd(ok) seconds earlier, because the
# only check ran before the restart. RAILS/BLOCKERS.md #2 records that as open
# with "nothing yet re-checks liveness after the restart". This is that check.
#
# The two failure shapes are distinguishable and it is worth saying which one
# happened, because they need different actions:
#
#   relayd died   443 refuses in ~30ms while the app still answers on its own
#                 port from the box. Every site is down. Not port 80 — relayd
#                 declares one relay, `listen on 0.0.0.0 port 443 tls`, so 80
#                 refuses on a healthy box and tests nothing.
#   app shed      443 still answers TLS and only the app port is closed. TLS
#                 answering is why a shed reads as curl 000 rather than a 5xx.
relayd_confirm_live() {
  local app_port=$1
  local deadline=20

  if ${_PRIV} ruby34 -e '
    require "socket"
    port, deadline = ARGV.map(&:to_i)
    deadline.times do
      begin
        Socket.tcp("127.0.0.1", port, connect_timeout: 1) { |s| s.close }
        exit 0
      rescue StandardError
        sleep 1
      end
    end
    exit 1
  ' 443 "$deadline"; then
    log_ok "relayd: 443 accepting after restart"
    return 0
  fi

  if ${_PRIV} ruby34 -e '
    require "socket"
    begin
      Socket.tcp("127.0.0.1", ARGV[0].to_i, connect_timeout: 1) { |s| s.close }
      exit 0
    rescue StandardError
      exit 1
    end
  ' "$app_port"; then
    log_err "relayd: 443 refused for ${deadline}s while the app still answers on ${app_port} — relayd is down, every site with it"
  else
    log_err "relayd: 443 refused for ${deadline}s and so did ${app_port} — check the app before blaming relayd"
  fi
  return 1
}

# relayd_add_relay DOMAIN PORT
# Idempotently adds a table + host-routing entry to /etc/relayd.conf for a new app,
# then restarts relayd if anything actually changed. Fails loudly (non-zero, caught
# by _deploy.sh's set -euo pipefail) on a sed insert that doesn't land -- a silently
# missing route is worse than an aborted deploy.
relayd_add_relay() {
  local domain=$1 port=$2
  local app=${domain%%.*}
  local conf=/etc/relayd.conf
  local changed=0

  [[ -f $conf ]] || { log_warn "relayd: ${conf} missing — skipping"; return 0; }

  if grep -qF "match request header \"Host\" value \"${domain}\"" "$conf" 2>/dev/null \
    && grep -qF "forward to <${app}> port ${port}" "$conf" 2>/dev/null; then
    log_ok "relayd: ${domain} already configured"
    return 0
  fi

  # OpenBSD sed -i takes the next arg as a backup suffix. GNU `sed -i "1a\\"`
  # without one is a no-op or a corrupt edit on the box. Rewrite in ruby.
  if ! grep -q "table <${app}>" "$conf" 2>/dev/null; then
    ${_PRIV} ruby34 -e '
      path, app = ARGV
      body = File.read(path)
      line = "table <#{app}> { 127.0.0.1 }\n"
      File.write(path, line + body) unless body.include?("table <#{app}>")
    ' "$conf" "$app" \
      || { log_err "relayd: could not add table <${app}>"; return 1; }
    log_ok "relayd: added table <${app}>"
    changed=1
  fi
  if ! grep -q "forward to <${app}>" "$conf" 2>/dev/null; then
    ${_PRIV} ruby34 -e '
      path, app, domain = ARGV
      body = File.read(path)
      line = "  match request header \"Host\" value \"#{domain}\" forward to <#{app}>\n"
      unless body.include?(line)
        File.write(path, body.sub(/match request header.*forward to <master>.*\n/) { |m| m + line })
      end
    ' "$conf" "$app" "$domain" \
      || { log_err "relayd: could not add Host routing for ${domain}"; return 1; }
    log_ok "relayd: added Host routing for ${domain}"
    changed=1
  fi
  if ! grep -q "forward to <${app}> port" "$conf" 2>/dev/null; then
    ${_PRIV} ruby34 -e '
      path, app, port = ARGV
      body = File.read(path)
      line = "  forward to <#{app}> port #{port} check http \"/up\" code 200\n"
      unless body.include?("forward to <#{app}> port")
        File.write(path, body.sub(/forward to <master> port.*\n/) { |m| m + line })
      end
    ' "$conf" "$app" "$port" \
      || { log_err "relayd: could not add forward for ${app}:${port}"; return 1; }
    log_ok "relayd: added forward to <${app}> port ${port}"
    changed=1
  fi

  if [[ $changed == 1 ]]; then
    ${_PRIV} rcctl restart relayd || { log_err "relayd: restart failed after config change"; return 1; }
    relayd_confirm_live "$port" || return 1
    log_ok "relayd: restarted to pick up ${domain}"
  fi
  return 0
}

# warm_brgen_after_restart — Falcon cold boot can exceed relayd/client timeouts
warm_brgen_after_restart() {
  local port=${1:-38182}
  sleep 8
  curl -fsS -m 120 -H "Host: brgen.no" "http://127.0.0.1:${port}/up" -o /dev/null 2>/dev/null \
    || log_warn "brgen warm /up skipped"
  curl -fsS -m 120 -H "Host: markedsplass.brgen.no" "http://127.0.0.1:${port}/" -o /dev/null 2>/dev/null \
    || log_warn "brgen warm marketplace skipped"
}
