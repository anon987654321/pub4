#!/usr/bin/env zsh
# @shared_functions.sh — shared helpers for DEPLOY/rails/* scripts
# Source this file; do not execute directly.
# Requires: zsh, ruby34, bundle, rails, doas
set -euo pipefail

PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"

if command -v doas >/dev/null 2>&1; then
  _PRIV=doas
else
  _PRIV=sudo
fi

: "${APP_PORT:=3000}"

log()      { print -P "%F{cyan}==>%f $*"; }
log_ok()   { print -P "%F{green}ok%f $*"; }
log_warn() { print -P "%F{yellow}WARN%f $*" >&2; }
log_err()  { print -P "%F{red}ERR%f $*" >&2; }

need_cmd() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || { log_err "Required: $cmd"; exit 1; }
    log_ok "$cmd found"
  done
}

already_done() {
  local sentinel=$1
  [[ -f $sentinel ]] && { log_warn "Already set up ($sentinel exists). Skipping."; return 0; }
  return 1
}

create_rails_app() {
  local app_dir=$1
  local app_name=${app_dir:t:h}
  mkdir -p "${app_dir:h}"
  if [[ ! -f "${app_dir}/config/application.rb" ]]; then
    log "Creating Rails 8 app at $app_dir"
    rails new "$app_dir" \
      --database=sqlite3 \
      --asset-pipeline=propshaft \
      --javascript=importmap \
      --skip-git \
      --skip-test \
      --skip-bundle
    # Bootstrap gems from amber to avoid OOM on fresh bundle install
    local bundle_home="/home/${app_dir:h:t}/.bundle"
    if [[ ! -d "${bundle_home}/gems" ]]; then
      log "Bootstrapping gems from amber"
      mkdir -p "${bundle_home}"
      cp -r /home/amber/.bundle/gems "${bundle_home}/"
      cp -r /home/amber/.bundle/cache "${bundle_home}/" 2>/dev/null || true
    fi
    mkdir -p "${app_dir}/.bundle"
    print "---\nBUNDLE_PATH: \"${bundle_home}/gems\"" > "${app_dir}/.bundle/config"
    cp /home/amber/app/Gemfile.lock "${app_dir}/Gemfile.lock"
  fi
  cd "$app_dir"
  log_ok "Working in: $app_dir"
}

add_gem() {
  local gem=$1 ver=${2:-}
  if ! grep -q "\"${gem}\"" Gemfile 2>/dev/null; then
    if [[ -n $ver ]]; then
      print "gem \"${gem}\", \"${ver}\"" >> Gemfile
    else
      print "gem \"${gem}\"" >> Gemfile
    fi
    log_ok "gem ${gem} added"
  else
    log_ok "gem ${gem} already present"
  fi
}

bundle_install() {
  bundle check 2>/dev/null && { log_ok "bundle ok (no install needed)"; return 0; }
  log "bundle install"
  bundle install --jobs=2 2>&1 | tail -5
  log_ok "bundle install done"
}

add_gem_group() {
  local groups=$1; shift
  local -a gems=("$@")
  if ! grep -q "gem \"${gems[1]}\"" Gemfile 2>/dev/null; then
    {
      print "group :${groups//,/, :} do"
      for g in "${gems[@]}"; do print "  gem \"$g\""; done
      print "end"
    } >> Gemfile
  fi
}

install_solid_stack() {
  log "Installing Solid Cache / Queue / Cable"
  add_gem solid_cache
  add_gem solid_queue
  add_gem solid_cable
  bin/rails solid_cache:install 2>/dev/null || true
  bin/rails solid_queue:install 2>/dev/null || true
  bin/rails solid_cable:install 2>/dev/null || true
  log_ok "Solid stack installed"
}

install_auth() {
  if [[ ! -f app/models/session.rb ]]; then
    log "Generating Rails 8 authentication"
    bin/rails generate authentication
    bin/rails db:migrate
  else
    log_ok "Authentication already generated"
  fi
}

install_active_storage() {
  if [[ -z $(print db/migrate/*create_active_storage*(N)) ]]; then
    log "Installing Active Storage"
    bin/rails active_storage:install
    bin/rails db:migrate
  else
    log_ok "Active Storage already installed"
  fi
}

install_action_text() {
  if [[ -z $(print db/migrate/*create_action_text*(N)) ]]; then
    log "Installing Action Text"
    bin/rails action_text:install
    bin/rails db:migrate
  else
    log_ok "Action Text already installed"
  fi
}

db_setup() {
  log "Setting up database"
  RAILS_ENV=production bin/rails db:create db:migrate
  log_ok "Database ready"
}

db_migrate() {
  RAILS_ENV=${RAILS_ENV:-production} bin/rails db:migrate
  log_ok "Migrations complete"
}

configure_production() {
  local cfg=config/environments/production.rb
  local text
  text=$(<"$cfg")
  [[ $text == *"assume_ssl"* ]] || print '  config.assume_ssl = true' >> "$cfg"
  [[ $text == *"solid_cache"* ]] || print '  config.cache_store = :solid_cache_store' >> "$cfg"
  log_ok "Production config updated"
}

install_security_tools() {
  add_gem_group "development,test" brakeman rubocop-rails-omakase
  log_ok "Security tools added"
}

# random_port — picks a random unused TCP port in 10000–62000.
# Usage: port=$(random_port)
random_port() {
  local port
  while true; do
    port=$(( RANDOM % 52000 + 10000 ))
    # Confirm nothing is bound to the port
    if ! nc -z 127.0.0.1 "$port" 2>/dev/null; then
      print "$port"
      return 0
    fi
  done
}

# install_rcd APP_NAME APP_DIR PORT SERVICE_NAME
# Installs or updates the rc.d service file for a Rails app on OpenBSD.
install_rcd() {
  local app_name=$1 app_dir=$2 port=$3 svc=${4:-$1}
  local rcd_src="$(dirname "$0")/../../openbsd/etc/rc.d/${svc}"
  local rcd_dst="/etc/rc.d/${svc}"
  if [[ ! -f $rcd_src ]]; then
    log_warn "rc.d template not found: $rcd_src — skipping install_rcd"
    return 0
  fi
  ${_PRIV} install -o root -g wheel -m 0555 "$rcd_src" "$rcd_dst"
  rcctl_ensure_service "$svc"
  log_ok "rc.d ${svc} installed and enabled"
}

# rcctl_ensure_service — idempotent enable + restart-or-start.
# Safe on first deploy (start) and subsequent deploys (restart).
rcctl_ensure_service() {
  local svc=$1
  ${_PRIV} rcctl enable "$svc" 2>/dev/null || true
  if ${_PRIV} rcctl check "$svc" 2>/dev/null | grep -q '(ok)'; then
    ${_PRIV} rcctl restart "$svc" 2>/dev/null || ${_PRIV} rcctl start "$svc"
  else
    ${_PRIV} rcctl start "$svc"
  fi
}

# relayd_add_relay DOMAIN PORT
# Idempotently adds a table + host-routing entry to /etc/relayd.conf for a new app.
# Run doas rcctl restart relayd after all relay additions are done.
relayd_add_relay() {
  local domain=$1 port=$2
  local app=${domain%%.*}
  local conf=/etc/relayd.conf
  # Add table if missing
  if ! grep -q "table <${app}>" "$conf" 2>/dev/null; then
    ${_PRIV} sed -i "1a table <${app}> { 127.0.0.1 }" "$conf"
    log_ok "relayd: added table <${app}>"
  fi
  # Add forward rule if missing
  if ! grep -q "forward to <${app}>" "$conf" 2>/dev/null; then
    ${_PRIV} sed -i "/match request header.*forward to <master>/a\\  match request header \"Host\" value \"${domain}\" forward to <${app}>" "$conf"
    log_ok "relayd: added Host routing for ${domain}"
  fi
  # Add forward target if missing
  if ! grep -q "forward to <${app}> port" "$conf" 2>/dev/null; then
    ${_PRIV} sed -i "/forward to <master> port/a\\  forward to <${app}> port ${port} check http \"/up\" code 200" "$conf"
    log_ok "relayd: added forward to <${app}> port ${port}"
  fi
}
