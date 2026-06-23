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

# master_scan_dep APP_NAME — rules.yml gate via MASTER CLI (requires bundle exec in MASTER/).
master_scan_dep() {
  local app_name=$1
  local master=${MASTER_ROOT:-/home/dev/pub4/MASTER}
  local log=/tmp/master_${app_name}_scan.log
  [[ -x ${master}/bin/cli ]] || return 0
  [[ -n ${SKIP_MASTER_SCAN:-} ]] && { log "MASTER scan skipped (SKIP_MASTER_SCAN)"; return 0; }
  log "MASTER rules scan (DEPLOY) pre-bundle"
  if ! (cd "$master" && MASTER_SCAN_ONLY=1 MASTER_SAFE_MODE=1 bundle_exec exec ruby bin/cli "/scan DEPLOY") \
    </dev/null >"$log" 2>&1; then
    cat "$log" >&2
    log_err "MASTER scan CLI failed"
    return 1
  fi
  cat "$log" >&2
  if grep -qE '[1-9][0-9]* total violations' "$log"; then
    log_err "MASTER scan found violations (evidence_scoring scan_clean gate)"
    return 1
  fi
  log_ok "MASTER scan clean"
}

bundle_exec() {
  local bundle_bin
  bundle_bin=$(command -v bundle34 2>/dev/null || command -v bundle)
  "$bundle_bin" "$@"
}

sync_tree() {
  local src=$1 dst=$2
  local delete=${3:-1}
  ${_PRIV} mkdir -p "$dst"
  if [[ $delete == 1 ]]; then
    ${_PRIV} openrsync -a --delete "${src%/}/." "${dst%/}/"
  else
    ${_PRIV} openrsync -a "${src%/}/." "${dst%/}/"
  fi
}

need_cmd() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || { log_err "Required: $cmd"; exit 1; }
    log_ok "$cmd found"
  done
}

# overlay_shared_initializers APP_DIR — shared config wins over stale per-app copies
overlay_shared_initializers() {
  local app_dir=$1
  local shared_init=${PUB4_DEPLOY_ROOT:-/home/dev/pub4/DEPLOY}/rails/shared/config/initializers
  [[ -d $shared_init ]] || return 0
  sync_tree "$shared_init" "${app_dir}/config/initializers"
  log_ok "shared initializers overlaid"
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
      ${_PRIV} mkdir -p "${bundle_home}/gems" "${bundle_home}/cache"
      ${_PRIV} openrsync -a /home/amber/.bundle/gems/ "${bundle_home}/gems/"
      ${_PRIV} openrsync -a /home/amber/.bundle/cache/ "${bundle_home}/cache/" 2>/dev/null || true
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

# master_web_assets_precompile — Propshaft digest manifest + digested files for production face UI.
master_web_assets_precompile() {
  local web_root=${1:-${PUB4:-/home/dev/pub4}/MASTER/web}
  [[ -d $web_root ]] || { log_warn "master_web_assets_precompile: missing ${web_root}"; return 0; }
  log "MASTER web assets:precompile"
  (
    cd "$web_root"
    rm -rf public/assets
    RAILS_ENV=production SECRET_KEY_BASE="${SECRET_KEY_BASE:-dummy}" bundle_exec exec rails assets:precompile
    bundle_exec exec ruby "${PUB4:-/home/dev/pub4}/DEPLOY/rails/master_web_assets_gate.rb"
  ) || { log_err "MASTER web assets precompile failed"; return 1; }
  log_ok "MASTER web assets ready"
}

# rails_runtime_gate APP_NAME APP_DIR — bundle check + db:prepare + bin/ci + master scan before rcctl restart.
rails_runtime_gate() {
  local app_name=${1:-}
  local app_dir=${2:-$1}
  [[ -d $app_dir ]] || { log_warn "rails_runtime_gate: missing ${app_dir}"; return 0; }
  [[ -n ${SKIP_RUNTIME_GATE:-} ]] && { log "runtime gate skipped (SKIP_RUNTIME_GATE)"; return 0; }
  if [[ -n $app_name ]]; then
    master_scan_dep "$app_name" || { log_err "MASTER scan failed"; return 1; }
  fi
  log "runtime gate: bundle check + db:prepare + bin/ci"
  (cd "$app_dir" && bundle_exec check) || { log_err "bundle check failed"; return 1; }
  (cd "$app_dir" && RAILS_ENV=production bundle_exec exec rails db:prepare) \
    || { log_err "db:prepare failed"; return 1; }
  if [[ -x ${app_dir}/bin/ci ]]; then
    (cd "$app_dir" && bundle_exec exec bin/ci) || { log_err "bin/ci failed"; return 1; }
  fi
  log_ok "runtime gate passed"
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

# app_secret_for APP_NAME — read or create SECRET_KEY_BASE in /etc/<app>.env
app_secret_for() {
  local app_name=$1 env_file secret

  for env_file in /etc/${app_name}.env /etc/rails/${app_name}.env; do
    if ${_PRIV} test -r "$env_file"; then
      secret=$(${_PRIV} grep '^SECRET_KEY_BASE=' "$env_file" | head -1 | cut -d= -f2-)
      [[ -n $secret ]] && { print -r -- "$secret"; return 0; }
    fi
  done

  secret=$(ruby34 -e "require 'securerandom'; puts SecureRandom.hex(64)")
  ${_PRIV} sh -c "print -r 'SECRET_KEY_BASE=${secret}' > /etc/${app_name}.env && chmod 640 /etc/${app_name}.env && chown root:${app_name} /etc/${app_name}.env 2>/dev/null || chown root:wheel /etc/${app_name}.env"
  log_ok "created /etc/${app_name}.env" >&2
  print -r -- "$secret"
}

# db_create_migrate_as_app APP_NAME APP_DIR
db_create_migrate_as_app() {
  local app_name=$1 app_dir=$2 secret
  secret=$(app_secret_for "$app_name")
  ${_PRIV} sh -c "su -m ${app_name} -c 'cd ${app_dir} && SECRET_KEY_BASE=${secret} RAILS_ENV=production bin/rails db:create db:migrate'"
  log_ok "Database ready"
}

# db_seed_as_app APP_NAME APP_DIR
db_seed_as_app() {
  local app_name=$1 app_dir=$2 secret
  secret=$(app_secret_for "$app_name")
  ${_PRIV} sh -c "su -m ${app_name} -c 'cd ${app_dir} && SECRET_KEY_BASE=${secret} RAILS_ENV=production bin/rails db:seed'" \
    || log_warn "db:seed skipped for ${app_name}"
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
  local deploy_root=${PUB4_DEPLOY_ROOT:-/home/dev/pub4/DEPLOY}
  local rcd_src="${deploy_root}/openbsd/etc/rc.d/${svc}"
  local rcd_dst="/etc/rc.d/${svc}"
  if [[ ! -f $rcd_src ]]; then
    log_warn "rc.d template not found: $rcd_src — skipping install_rcd"
    return 0
  fi
  ${_PRIV} install -o root -g wheel -m 0555 "$rcd_src" "$rcd_dst"
  assert_rcd_identity "$svc" "$app_name" "$app_dir"
  ${_PRIV} rcctl enable "$svc"
  log_ok "rc.d ${svc} installed and enabled"
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

# relayd_add_relay DOMAIN PORT
# Idempotently adds a table + host-routing entry to /etc/relayd.conf for a new app.
# Run doas rcctl restart relayd after all relay additions are done.
relayd_add_relay() {
  local domain=$1 port=$2
  local app=${domain%%.*}
  local conf=/etc/relayd.conf

  [[ -f $conf ]] || { log_warn "relayd: ${conf} missing — skipping"; return 0; }

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
