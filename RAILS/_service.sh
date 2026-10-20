#!/usr/bin/env zsh
# _service.sh — rc.d service installation and relayd routing for copy-tree deploy.
# Source this file; do not execute directly. Requires _core.sh sourced first.
set -euo pipefail

# retire_legacy_rails_rcd APP_NAME — stop duplicate *_rails services from older bootstrap.
retire_legacy_rails_rcd() {
  local app_name=$1 legacy="${app_name}_rails"
  [[ -f /etc/rc.d/$legacy ]] || return 0
  [[ -x /usr/local/sbin/pub4-admin ]] || {
    log_err "retire_legacy_rails_rcd: pub4-admin is missing; run OPERATOR.sh before deploying"
    return 1
  }
  "${_PRIV}" /usr/local/sbin/pub4-admin retire-legacy "$app_name" \
    || { log_err "could not disable legacy service ${legacy}"; return 1; }
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
# Service files are installed by the reviewed operator sync, never copied from
# the deploy account's writable checkout during an app deploy.
install_rcd() {
  local app_name=$1 app_dir=$2 port=$3 svc=${4:-$1}
  local rcd_dst="/etc/rc.d/${svc}"
  if [[ ! -f $rcd_dst || -L $rcd_dst ]]; then
    log_err "rc.d ${svc} is missing or symlinked — run the reviewed OPENBSD/OPERATOR.sh sync first"
    return 1
  fi
  local owner mode
  owner=$(/usr/bin/stat -f %u "$rcd_dst") || return 1
  mode=$(/usr/bin/stat -f %Lp "$rcd_dst") || return 1
  [[ $owner == 0 && $mode == 555 ]] || {
    log_err "rc.d ${svc} must be root-owned mode 555; run the reviewed OPENBSD/OPERATOR.sh sync first"
    return 1
  }
  assert_rcd_identity "$svc" "$app_name" "$app_dir"
  retire_legacy_rails_rcd "$app_name"
  log_ok "rc.d ${svc} verified (operator-installed, root-owned, mode 555)"
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
# only check ran before the restart. the old backlog #2 records that as open
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

  if "$RUBY" -e '
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

  if "$RUBY" -e '
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

# relayd_add_relay APP_NAME DOMAIN PORT
# Verifies the root-owned Host route and backend for this app. The installed broker
# is read-only here; new Host routes must be added through OPERATOR.sh first.
relayd_add_relay() {
  local app=$1 domain=$2 port=$3

  case "$app" in brgen|amber|bsdports) ;; *) log_err "relayd: refused unknown app: $app"; return 2 ;; esac
  [[ $domain == *.* ]] || { log_err "relayd: refused invalid domain"; return 2; }
  [[ $port == <-> ]] || { log_err "relayd: refused invalid port"; return 2; }

  [[ -x /usr/local/sbin/pub4-admin ]] || {
    log_err "relayd: fixed broker is missing; run OPERATOR.sh before deploying"
    return 1
  }
  ${_PRIV} /usr/local/sbin/pub4-admin relayd-check "$app" "$domain" "$port" \
    || { log_err "relayd: root-approved route check failed for ${domain}"; return 1; }
  relayd_confirm_live "$port" || return 1
  log_ok "relayd: ${domain} verified for ${app}:${port}"
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
