#!/usr/bin/env zsh
# @service.sh — rc.d service installation and relayd routing for copy-tree deploy.
# Source this file; do not execute directly. Requires @core.sh sourced first.

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

# relayd_add_relay DOMAIN PORT
# Idempotently adds a table + host-routing entry to /etc/relayd.conf for a new app.
# Run doas rcctl restart relayd after all relay additions are done.
relayd_add_relay() {
  local domain=$1 port=$2
  local app=${domain%%.*}
  local conf=/etc/relayd.conf

  [[ -f $conf ]] || { log_warn "relayd: ${conf} missing — skipping"; return 0; }

  if grep -qF "match request header \"Host\" value \"${domain}\"" "$conf" 2>/dev/null \
    && grep -qF "forward to <${app}> port ${port}" "$conf" 2>/dev/null; then
    log_ok "relayd: ${domain} already configured"
    return 0
  fi

  if ! grep -q "table <${app}>" "$conf" 2>/dev/null; then
    ${_PRIV} sed -i "1a\\
table <${app}> { 127.0.0.1 }\\
" "$conf" 2>/dev/null \
      || { log_warn "relayd: could not add table <${app}>"; return 0; }
    log_ok "relayd: added table <${app}>"
  fi
  if ! grep -q "forward to <${app}>" "$conf" 2>/dev/null; then
    ${_PRIV} sed -i "/match request header.*forward to <master>/a\\
  match request header \"Host\" value \"${domain}\" forward to <${app}>\\
" "$conf" 2>/dev/null \
      || { log_warn "relayd: could not add Host routing for ${domain}"; return 0; }
    log_ok "relayd: added Host routing for ${domain}"
  fi
  if ! grep -q "forward to <${app}> port" "$conf" 2>/dev/null; then
    ${_PRIV} sed -i "/forward to <master> port/a\\
  forward to <${app}> port ${port} check http \"/up\" code 200\\
" "$conf" 2>/dev/null \
      || { log_warn "relayd: could not add forward for ${app}:${port}"; return 0; }
    log_ok "relayd: added forward to <${app}> port ${port}"
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
