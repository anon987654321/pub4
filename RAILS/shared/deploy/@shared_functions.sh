#!/usr/bin/env zsh
# @shared_functions.sh — shared helpers for RAILS/* scripts
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
  log "MASTER rules scan (OPERATOR) pre-bundle"
  if ! (cd "$master" && MASTER_SCAN_ONLY=1 MASTER_SAFE_MODE=1 bundle_exec exec ruby bin/cli "/scan OPERATOR") \
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
  if [[ -n ${SYNC_USE_OPENRSYNC:-} ]]; then
    if [[ $delete == 1 ]]; then
      ${_PRIV} openrsync -a --delete "${src%/}/." "${dst%/}/" && return 0
    else
      ${_PRIV} openrsync -a "${src%/}/." "${dst%/}/" && return 0
    fi
    log_warn "openrsync failed; falling back to tar copy"
  fi
  if [[ $delete == 1 ]]; then
    ${_PRIV} sh -c 'cd "$1" && for entry in * .[!.]* ..?*; do
      [[ -e "$entry" ]] || continue
      case "$entry" in db|storage|log|tmp|vendor|.bundle) continue ;; esac
      rm -rf -- "$entry"
    done' _ "${dst%/}" 2>/dev/null || true
  fi
  ${_PRIV} sh -c "cd '${src%/}' && tar cf - ." | ${_PRIV} sh -c "cd '${dst%/}' && tar xf -"
  ${_PRIV} find "${dst%/}" -name '._*' -delete 2>/dev/null || true
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
  local shared_init=${PUB4_DEPLOY_ROOT:-/home/dev/pub4/OPERATOR}/rails/shared/config/initializers
  [[ -d $shared_init ]] || return 0
  sync_tree "$shared_init" "${app_dir}/config/initializers"
  log_ok "shared initializers overlaid"
}

# overlay_shared_public APP_DIR — merge shared/public (tokens.css, minimal-ui.css, icons)
overlay_shared_public() {
  local app_dir=$1
  local shared_public=${PUB4_DEPLOY_ROOT:-/home/dev/pub4/OPERATOR}/rails/shared/public
  [[ -d $shared_public ]] || return 0
  sync_tree "$shared_public" "${app_dir}/public" 0
  log_ok "shared public assets overlaid"
  overlay_shared_bin "$app_dir"
}

# overlay_shared_bin APP_DIR — ci.rb expects bin/rubocop, brakeman, bundler-audit stubs
overlay_shared_bin() {
  local app_dir=$1
  local shared_bin=${PUB4_DEPLOY_ROOT:-/home/dev/pub4/OPERATOR}/rails/shared/bin
  [[ -d $shared_bin ]] || return 0
  ${_PRIV} mkdir -p "${app_dir}/bin"
  for tool in rubocop brakeman bundler-audit; do
    [[ -f ${shared_bin}/${tool} ]] || continue
    ${_PRIV} cp "${shared_bin}/${tool}" "${app_dir}/bin/${tool}"
    ${_PRIV} chmod 755 "${app_dir}/bin/${tool}"
  done
  [[ -f ${PUB4_DEPLOY_ROOT:-/home/dev/pub4/OPERATOR}/rails/shared/.rubocop.yml ]] \
    && ${_PRIV} cp "${PUB4_DEPLOY_ROOT:-/home/dev/pub4/OPERATOR}/rails/shared/.rubocop.yml" "${app_dir}/.rubocop.yml"
  log_ok "shared bin stubs overlaid"
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
    bundle_exec exec ruby "${PUB4:-/home/dev/pub4}/RAILS/master_web_assets_gate.rb"
  ) || { log_err "MASTER web assets precompile failed"; return 1; }
  log_ok "MASTER web assets ready"
}

# ensure_npm_cache APP_NAME — sass-embedded native build must not write /root/.npm via doas.
ensure_npm_cache() {
  local app_name=$1
  local npm_cache="/home/${app_name}/.npm"
  ${_PRIV} mkdir -p "$npm_cache"
  ${_PRIV} chown "${app_name}:${app_name}" "$npm_cache"
}

# bundle_install_as_app APP_NAME APP_DIR — production bundle as app user with app-owned npm cache.
bundle_install_as_app() {
  local app_name=$1
  local app_dir=$2
  ensure_npm_cache "$app_name"
  local npm_cache="/home/${app_name}/.npm"
  ${_PRIV} sh -c "su -m ${app_name} -c 'export HOME=/home/${app_name}; export NPM_CONFIG_CACHE=${npm_cache}; cd ${app_dir} && bundle config set --local frozen false && bundle config set --local deployment true && bundle config set --local without \"development test\" && RAILS_ENV=production bundle install'"
}

# rails_prepare_secondary_dbs_as_app APP_NAME APP_DIR — load cache/queue/cable schemas on copy-tree deploy.
rails_prepare_secondary_dbs_as_app() {
  local app_name=$1
  local app_dir=$2
  local secret
  secret=$(app_secret_for "$app_name")
  local db
  for db in cache queue cable; do
    local schema="${app_dir}/db/${db}_schema.rb"
    [[ -f $schema ]] || continue
    grep -q 'define(version: 0)' "$schema" 2>/dev/null && continue
    log "db:schema:load:${db} for ${app_name}"
    run_rails_as_app "$app_name" "$app_dir" \
      "SECRET_KEY_BASE=${secret} DISABLE_DATABASE_ENVIRONMENT_CHECK=1 RAILS_ENV=production bundle34 exec rails db:schema:load:${db}" \
      || { log_err "db:schema:load:${db} failed for ${app_name}"; return 1; }
  done
}

# rails_assets_precompile_as_app APP_NAME APP_DIR — Propshaft digest manifest for production JS/CSS.
rails_assets_precompile_as_app() {
  local app_name=$1
  local app_dir=$2
  local secret
  secret=$(app_secret_for "$app_name")
  log "assets:precompile for ${app_name}"
  run_rails_as_app "$app_name" "$app_dir" \
    "SECRET_KEY_BASE=${secret} RAILS_ENV=production bundle34 exec rails assets:precompile" \
    || { log_err "assets:precompile failed for ${app_name}"; return 1; }
  log_ok "assets ready for ${app_name}"
}

# run_rails_as_app APP_NAME APP_DIR CMD — app-owned bundle/rails (avoids Gemfile.lock permission errors).
run_rails_as_app() {
  local app_name=$1 app_dir=$2
  shift 2
  ensure_npm_cache "$app_name"
  local npm_cache="/home/${app_name}/.npm"
  ${_PRIV} sh -c "su -m ${app_name} -c 'export HOME=/home/${app_name}; export NPM_CONFIG_CACHE=${npm_cache}; cd ${app_dir} && $*'"
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
  log "runtime gate: ci bundle + db:prepare + bin/ci"
  if [[ -n $app_name ]]; then
    local secret
    secret=$(app_secret_for "$app_name")
    run_rails_as_app "$app_name" "$app_dir" \
      "bundle34 config unset without && bundle34 install --jobs=2" \
      || { log_err "ci bundle install failed"; return 1; }
    run_rails_as_app "$app_name" "$app_dir" bundle34 check \
      || { log_err "bundle check failed"; return 1; }
    run_rails_as_app "$app_name" "$app_dir" \
      "SECRET_KEY_BASE=${secret} RAILS_ENV=production bundle34 exec rails db:prepare" \
      || { log_err "db:prepare failed"; return 1; }
    rails_prepare_secondary_dbs_as_app "$app_name" "$app_dir" \
      || return 1
    rails_assets_precompile_as_app "$app_name" "$app_dir" \
      || return 1
    if [[ -x ${app_dir}/bin/ci ]]; then
      local rails_tree=${PUB4_DEPLOY_ROOT:-/home/dev/pub4/OPERATOR}/rails
      if [[ -d $rails_tree ]]; then
        chmod o+x /home/dev 2>/dev/null || true
        chmod -R a+rX "$rails_tree" 2>/dev/null || true
      fi
      run_rails_as_app "$app_name" "$app_dir" \
        "SECRET_KEY_BASE=${secret} PUB4_RAILS_ROOT=${rails_tree} RAILS_ENV=test CI=1 PUB4_CI_GUARD=1 bundle34 exec bin/ci" \
        || { log_err "bin/ci failed"; return 1; }
    fi
  else
    (cd "$app_dir" && bundle_exec check) || { log_err "bundle check failed"; return 1; }
    (cd "$app_dir" && RAILS_ENV=production bundle_exec exec rails db:prepare) \
      || { log_err "db:prepare failed"; return 1; }
    if [[ -x ${app_dir}/bin/ci ]]; then
      (cd "$app_dir" && bundle_exec exec bin/ci) || { log_err "bin/ci failed"; return 1; }
    fi
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
  ${_PRIV} sh -c "su -m ${app_name} -c 'cd ${app_dir} && SECRET_KEY_BASE=${secret} RAILS_ENV=production bundle34 exec rails db:prepare'" \
    || { log_err "db:prepare failed for ${app_name}"; return 1; }
  rails_prepare_secondary_dbs_as_app "$app_name" "$app_dir" \
    || return 1
  log_ok "Database ready"
}

# migrate_sqlite_db_to_storage_if_needed APP_NAME APP_DIR — one-time brgen db/ → storage/ move (R7).
migrate_sqlite_db_to_storage_if_needed() {
  local app_name=$1 app_dir=$2
  local db_dir="${app_dir}/db" storage_dir="${app_dir}/storage"
  [[ -d $db_dir ]] || return 0
  ${_PRIV} mkdir -p "$storage_dir"
  local moved=0 base
  for f in ${db_dir}/production*.sqlite3(N); do
    base=${f:t}
    [[ -f ${storage_dir}/${base} ]] && continue
    ${_PRIV} mv "$f" "${storage_dir}/${base}"
    moved=1
    log_ok "moved db/${base} → storage/${base}"
  done
  if [[ $moved -eq 1 ]]; then
    ${_PRIV} chown -R "${app_name}:${app_name}" "$storage_dir"
  fi
}

# seed_bergen_demo_as_app — credible brgen.no feed (no Faker flood)
seed_bergen_demo_as_app() {
  local app_dir=$1 secret
  secret=$(app_secret_for brgen)
  ${_PRIV} sh -c "su -m brgen -c 'cd ${app_dir} && SECRET_KEY_BASE=${secret} RAILS_ENV=production bundle34 exec rails brgen:demo_seed'" \
    || log_warn "brgen:demo_seed skipped"
}

# seed_amber_demo_as_app — public demo capsule wardrobe for guests
seed_amber_demo_as_app() {
  local app_dir=$1 secret
  secret=$(app_secret_for amber)
  ${_PRIV} sh -c "su -m amber -c 'cd ${app_dir} && SECRET_KEY_BASE=${secret} RAILS_ENV=production bundle34 exec rails amber:demo_seed'" \
    || log_warn "amber:demo_seed skipped"
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

# db_seed_as_app APP_NAME APP_DIR
db_seed_as_app() {
  local app_name=$1 app_dir=$2 secret
  secret=$(app_secret_for "$app_name")
  ${_PRIV} sh -c "su -m ${app_name} -c 'cd ${app_dir} && SECRET_KEY_BASE=${secret} RAILS_ENV=production bundle34 exec rails db:seed'" \
    || log_warn "db:seed skipped for ${app_name}"
}

# brgen cannot read /home/dev (mode 700) — copy Radio Bergen manifest into the app tree.
overlay_brgen_radio_manifest() {
  local app_dir=$1
  local repo=${PUB4_ROOT:-/home/dev/pub4}
  local manifest=${repo}/MASTER/tools/audio/radio_bergen_tracks.yml
  local lessons=${repo}/MASTER/data/lessons/pub_archive_restore.yml

  [[ -f $manifest ]] || { log_err "missing Radio Bergen manifest: $manifest"; exit 1; }

  doas mkdir -p "${app_dir}/config/radio_bergen"
  doas cp "$manifest" "${app_dir}/config/radio_bergen/tracks.yml"
  [[ -f $lessons ]] && doas cp "$lessons" "${app_dir}/config/radio_bergen/archive_lessons.yml"
  doas chown -R brgen:brgen "${app_dir}/config/radio_bergen"
  log "ok Radio Bergen manifest overlaid → config/radio_bergen/"
}

# deploy_tracked_app APP_NAME — copy the app tree, install bundle/db/service, then restart.
deploy_tracked_app() {
  local app_name=${1:-$APP_NAME}

  need_cmd ruby34 bundle doas

  [[ -d $SRC_DIR ]] || { log_err "missing source tree: $SRC_DIR"; exit 1; }

  log "${app_name} — deploying tracked tree → ${APP_DIR}"

  id "$app_name" >/dev/null 2>&1 || doas useradd -m -L daemon -s /bin/ksh "$app_name"
  doas mkdir -p "$APP_DIR"

  sync_tree "${SRC_DIR}/" "${APP_DIR}"
  doas rm -rf "/home/${app_name}/shared"
  sync_tree /home/dev/pub4/RAILS/shared "/home/${app_name}/shared"
  doas chown -R "${app_name}:${app_name}" "/home/${app_name}/shared"
  doas chown -R "${app_name}:${app_name}" "$APP_DIR"
  overlay_shared_initializers "$APP_DIR"
  overlay_shared_public "$APP_DIR"
  if [[ $app_name == brgen ]]; then
    overlay_brgen_radio_manifest "$APP_DIR"
  fi
  doas chown -R "${app_name}:${app_name}" "$APP_DIR"

  if ! master_scan_dep "$app_name"; then
    log "MASTER scan violations — aborting per rules.yml"
    exit 1
  fi

  cd "$APP_DIR"

  typeset bundle_home="/home/${app_name}/.bundle"
  doas mkdir -p "$bundle_home"

  if [[ ! -d ${bundle_home}/gems ]]; then
    if [[ -d ${SHARED_BUNDLE_CACHE}/gems ]]; then
      log "Bootstrapping gems from ${SHARED_BUNDLE_CACHE}"
      doas mkdir -p "${bundle_home}/gems" "${bundle_home}/cache"
      doas openrsync -a "${SHARED_BUNDLE_CACHE}/gems/" "${bundle_home}/gems/"
      [[ -d ${SHARED_BUNDLE_CACHE}/cache ]] && doas openrsync -a "${SHARED_BUNDLE_CACHE}/cache/" "${bundle_home}/cache/" || true
    elif [[ -d /home/amber/.bundle/gems && ${bundle_home} != /home/amber/.bundle ]]; then
      log "Bootstrapping gems from /home/amber/.bundle"
      doas mkdir -p "${bundle_home}/gems" "${bundle_home}/cache"
      doas openrsync -a /home/amber/.bundle/gems/ "${bundle_home}/gems/"
      [[ -d /home/amber/.bundle/cache ]] && doas openrsync -a /home/amber/.bundle/cache/ "${bundle_home}/cache/" || true
    else
      log_warn "No shared bundle cache found; bundle install will resolve gems normally"
    fi
    doas chown -R "${app_name}:${app_name}" "$bundle_home"
  fi

  doas mkdir -p "${APP_DIR}/.bundle"
  print -- "---\nBUNDLE_PATH: \"${bundle_home}/gems\"" | doas tee "${APP_DIR}/.bundle/config" >/dev/null
  doas chown -R "${app_name}:${app_name}" "${APP_DIR}/.bundle"

  bundle_install_as_app "$APP_NAME" "$APP_DIR"
  log_ok "production bundle installed for ${app_name}"
  migrate_sqlite_db_to_storage_if_needed "$APP_NAME" "$APP_DIR"
  # Stop the running app before touching its SQLite db: db:prepare/migrate hangs
  # indefinitely waiting on the write lock a live Falcon worker already holds,
  # which silently swallowed every deploy's runtime gate (precompile + bin/ci)
  # behind it -- this app_name may not have a running service yet on first deploy.
  doas rcctl stop "$app_name" 2>/dev/null || true
  db_create_migrate_as_app "$APP_NAME" "$APP_DIR" || exit 1
  log_ok "database migrated for ${app_name}"
  if [[ -f ${APP_DIR}/db/seeds.rb && ${SEED_ON_DEPLOY:-} == 1 ]]; then
    db_seed_as_app "$APP_NAME" "$APP_DIR"
  fi

  install_rcd "$APP_NAME" "$APP_DIR" "$APP_PORT" "$APP_NAME"
  [[ -n $APP_DOMAIN ]] && relayd_add_relay "$APP_DOMAIN" "$APP_PORT"

  rails_runtime_gate "$APP_NAME" "$APP_DIR" || exit 1
  if [[ $app_name == brgen ]]; then
    seed_bergen_demo_as_app "$APP_DIR"
  elif [[ $app_name == amber ]]; then
    seed_amber_demo_as_app "$APP_DIR"
  fi
  doas rcctl restart "$APP_NAME" || doas rcctl start "$APP_NAME"
  if [[ $app_name == brgen ]]; then
    warm_brgen_after_restart "$APP_PORT"
  fi
  log_ok "$APP_NAME live on :$APP_PORT"
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

# retire_legacy_rails_rcd APP_NAME — stop duplicate *_rails services from older bootstrap.
retire_legacy_rails_rcd() {
  local app_name=$1 legacy="${app_name}_rails"
  [[ -f /etc/rc.d/$legacy ]] || return 0
  ${_PRIV} rcctl disable "$legacy" 2>/dev/null || true
  log_ok "disabled legacy rc.d ${legacy} (no stop — shared port with ${app_name})"
}

# install_rcd APP_NAME APP_DIR PORT SERVICE_NAME
# Installs or updates the rc.d service file for a Rails app on OpenBSD.
install_rcd() {
  local app_name=$1 app_dir=$2 port=$3 svc=${4:-$1}
  local deploy_root=${PUB4_DEPLOY_ROOT:-/home/dev/pub4/OPERATOR}
  local rcd_src="${deploy_root}/openbsd/etc/rc.d/${svc}"
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
