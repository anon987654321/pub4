#!/usr/bin/env zsh
set -euo pipefail
# _runtime_gate.sh — MASTER rules scan and the full CI gate (bundle + db:prepare
# + bin/ci) that must pass before a deploy is allowed to restart the service.
# Source this file; do not execute directly. Requires _core.sh sourced first.

# master_scan_dep APP_NAME — laws.yml gate via MASTER CLI (requires bundle exec in MASTER/).
master_scan_dep() {
  local app_name=$1
  local master=${MASTER_ROOT:-/home/dev/pub4/MASTER}
  local log_dir=/var/db/pub4
  local log=${log_dir}/master_${app_name}_scan.log
  if [[ ${SKIP_MASTER_SCAN:-0} != 0 ]]; then
    if [[ ${SKIP_MASTER_SCAN} != 1 || ${I_UNDERSTAND_FAST_DEPLOY:-0} != 1 ]]; then
      log_err "SKIP_MASTER_SCAN=1 requires I_UNDERSTAND_FAST_DEPLOY=1"
      return 1
    fi
    log_warn "MASTER scan skipped by explicit fast-deploy acknowledgement"
    return 0
  fi
  [[ -x ${master}/bin/cli ]] || { log_err "MASTER scan unavailable at ${master}"; return 1; }
  mkdir -p "$log_dir" || { log_err "cannot create ${log_dir} for MASTER scan log"; return 1; }
  chmod 700 "$log_dir"
  log "MASTER rules scan (OPERATOR) pre-bundle"
  if ! (cd "$master" && MASTER_SCAN_DETERMINISTIC=1 MASTER_SAFE_MODE=1 bundle_exec exec ruby bin/gate --scan-only --tree=RAILS) \
    </dev/null >"$log" 2>&1; then
    cat "$log" >&2
    log_err "MASTER scan CLI failed"
    return 1
  fi
  cat "$log" >&2
  if grep -Eq '[1-9][0-9]* total violations|scan[0-9]*: .*([1-9][0-9]*) violations' "$log"; then
    log_err "MASTER scan found violations (evidence_scoring scan_clean gate)"
    return 1
  fi
  log_ok "MASTER scan clean"
}

# run_rails_as_app APP_NAME APP_DIR CMD — app-owned bundle/rails (avoids Gemfile.lock permission errors).
run_rails_as_app() {
  local app_name=$1 app_dir=$2 task=${3:-} database=${4:-}
  local secret command npm_cache
  case "$app_name" in master|brgen|amber|bsdports) ;; *) log_err "run_rails_as_app: refused app: $app_name"; return 2 ;; esac
  [[ $app_dir == "/home/${app_name}/app" ]] || { log_err "run_rails_as_app: refused app path: $app_dir"; return 2; }
  case "$task" in
    bundle-install|ci-bundle-install|bundle-check|db-storage-migrate|db-prepare|db-seed|demo-seed|assets-precompile|ci) [[ -z $database ]] || return 2 ;;
    schema-load|secondary-db-check) [[ $database == cache || $database == queue || $database == cable ]] || return 2 ;;
    *) log_err "run_rails_as_app: refused task: $task"; return 2 ;;
  esac
  [[ $task != demo-seed || $app_name == brgen || $app_name == amber ]] || return 2

  if [[ -x /usr/local/sbin/pub4-admin ]]; then
    if [[ $task == schema-load || $task == secondary-db-check ]]; then
      ${_PRIV} /usr/local/sbin/pub4-admin rails-task "$app_name" "$task" "$database"
    else
      ${_PRIV} /usr/local/sbin/pub4-admin rails-task "$app_name" "$task"
    fi
    return $?
  fi

  ensure_npm_cache "$app_name"
  npm_cache="/home/${app_name}/.npm"
  case "$task" in
    bundle-install)
      command="${BUNDLE} config set --local frozen false && ${BUNDLE} config set --local deployment true && ${BUNDLE} config set --local without \"development test\" && RAILS_ENV=production ${BUNDLE} install" ;;
    ci-bundle-install)
      command="${BUNDLE} config unset without && ${BUNDLE} install --jobs=2" ;;
    db-storage-migrate)
      command='[ -d db ] && [ ! -L db ] || exit 0
[ ! -L storage ] || { echo "rails-task: refusing storage symlink" >&2; exit 1; }
mkdir -p storage
for file in db/production*.sqlite3; do
  [ -f "$file" ] && [ ! -L "$file" ] || continue
  base=${file##*/}
  target="storage/$base"
  if [ -e "$target" ] || [ -L "$target" ]; then continue; fi
  mv "$file" "$target"
  printf "moved %s -> %s\\n" "$file" "$target"
done' ;;
    bundle-check)
      command="${BUNDLE} check" ;;
    db-prepare)
      secret=$(app_secret_for "$app_name") || return 1
      case "$secret" in ''|*[!0123456789abcdefABCDEF]*) log_err "invalid SECRET_KEY_BASE"; return 1 ;; esac
      (( ${#secret} >= 64 && ${#secret} <= 256 )) || { log_err "invalid SECRET_KEY_BASE length"; return 1; }
      command="SECRET_KEY_BASE=${secret} RAILS_ENV=production ${BUNDLE} exec rails db:prepare" ;;
    db-seed)
      secret=$(app_secret_for "$app_name") || return 1
      case "$secret" in ''|*[!0123456789abcdefABCDEF]*) log_err "invalid SECRET_KEY_BASE"; return 1 ;; esac
      (( ${#secret} >= 64 && ${#secret} <= 256 )) || { log_err "invalid SECRET_KEY_BASE length"; return 1; }
      command="SECRET_KEY_BASE=${secret} RAILS_ENV=production ${BUNDLE} exec rails db:seed" ;;
    demo-seed)
      secret=$(app_secret_for "$app_name") || return 1
      case "$secret" in ''|*[!0123456789abcdefABCDEF]*) log_err "invalid SECRET_KEY_BASE"; return 1 ;; esac
      (( ${#secret} >= 64 && ${#secret} <= 256 )) || { log_err "invalid SECRET_KEY_BASE length"; return 1; }
      command="SECRET_KEY_BASE=${secret} RAILS_ENV=production ${BUNDLE} exec rails ${app_name}:demo_seed" ;;
    assets-precompile)
      secret=$(app_secret_for "$app_name") || return 1
      case "$secret" in ''|*[!0123456789abcdefABCDEF]*) log_err "invalid SECRET_KEY_BASE"; return 1 ;; esac
      (( ${#secret} >= 64 && ${#secret} <= 256 )) || { log_err "invalid SECRET_KEY_BASE length"; return 1; }
      command="SECRET_KEY_BASE=${secret} RAILS_ENV=production ${BUNDLE} exec rails assets:precompile" ;;
    ci)
      secret=$(app_secret_for "$app_name") || return 1
      case "$secret" in ''|*[!0123456789abcdefABCDEF]*) log_err "invalid SECRET_KEY_BASE"; return 1 ;; esac
      (( ${#secret} >= 64 && ${#secret} <= 256 )) || { log_err "invalid SECRET_KEY_BASE length"; return 1; }
      local rails_tree=${PUB4_RAILS_ROOT:-/home/dev/pub4/RAILS}
      command="SECRET_KEY_BASE=${secret} PUB4_RAILS_ROOT=${rails_tree} RAILS_ENV=test CI=1 PUB4_CI_GUARD=1 ${BUNDLE} exec bin/ci" ;;
    schema-load)
      secret=$(app_secret_for "$app_name") || return 1
      case "$secret" in ''|*[!0123456789abcdefABCDEF]*) log_err "invalid SECRET_KEY_BASE"; return 1 ;; esac
      (( ${#secret} >= 64 && ${#secret} <= 256 )) || { log_err "invalid SECRET_KEY_BASE length"; return 1; }
      command="SECRET_KEY_BASE=${secret} DISABLE_DATABASE_ENVIRONMENT_CHECK=1 RAILS_ENV=production ${BUNDLE} exec rails db:schema:load:${database}" ;;
    secondary-db-check)
      return 1 ;; # The fallback path below still owns the legacy sqlite3 check.
  esac
  ${_PRIV} sh -c "su -m ${app_name} -c 'export HOME=/home/${app_name}; export NPM_CONFIG_CACHE=${npm_cache}; export XDG_CACHE_HOME=/home/${app_name}/.cache; export BUNDLE_USER_HOME=/home/${app_name}/.bundle; unset RUBYOPT RUBYLIB RUBYPATH RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_WITH BUNDLE_WITHOUT; cd ${app_dir} && ${command}'"
}

# rails_runtime_gate APP_NAME APP_DIR — bundle check + db:prepare + bin/ci + master scan before rcctl restart.
rails_runtime_gate() {
  local app_name=${1:-}
  local app_dir=${2:-$1}
  [[ -d $app_dir ]] || { log_warn "rails_runtime_gate: missing ${app_dir}"; return 0; }
  if [[ ${SKIP_RUNTIME_GATE:-} == 1 ]]; then
    if [[ ${I_UNDERSTAND_FAST_DEPLOY:-0} != 1 ]]; then
      log_err "runtime gate skip requires I_UNDERSTAND_FAST_DEPLOY=1"
      return 1
    fi
    log_warn "runtime gate skipped by explicit fast-deploy acknowledgement"
    return 0
  fi
  if [[ -n $app_name ]]; then
    master_scan_dep "$app_name" || { log_err "MASTER scan failed"; return 1; }
  fi
  log "runtime gate: ci bundle + db:prepare + bin/ci"
  if [[ -n $app_name ]]; then
    local secret
    secret=$(app_secret_for "$app_name")
    deploy_status "$app_name" "runtime gate: bundle install"
    run_rails_as_app "$app_name" "$app_dir" \
      "ci-bundle-install" \
      || { deploy_status "$app_name" "runtime gate: bundle install" "failed"; log_err "ci bundle install failed"; return 1; }
    deploy_status "$app_name" "runtime gate: bundle check"
    run_rails_as_app "$app_name" "$app_dir" "bundle-check" \
      || { deploy_status "$app_name" "runtime gate: bundle check" "failed"; log_err "bundle check failed"; return 1; }
    deploy_status "$app_name" "runtime gate: db:prepare"
    run_rails_as_app "$app_name" "$app_dir" \
      "db-prepare" \
      || { deploy_status "$app_name" "runtime gate: db:prepare" "failed"; log_err "db:prepare failed"; return 1; }
    deploy_status "$app_name" "runtime gate: secondary dbs"
    rails_prepare_secondary_dbs_as_app "$app_name" "$app_dir" \
      || { deploy_status "$app_name" "runtime gate: secondary dbs" "failed"; return 1; }
    deploy_status "$app_name" "runtime gate: assets precompile"
    rails_assets_precompile_as_app "$app_name" "$app_dir" \
      || { deploy_status "$app_name" "runtime gate: assets precompile" "failed"; return 1; }
    if [[ -x ${app_dir}/bin/ci ]]; then
      local rails_tree=${PUB4_RAILS_ROOT:-/home/dev/pub4/RAILS}
      if [[ -d $rails_tree ]]; then
        # traversal is group-based (710 dev:_pub4ci) — vps_ci.sh converges it;
        # this gate must not widen /home/dev to the world.
        chmod -R a+rX "$rails_tree" 2>/dev/null || true
      fi
      deploy_status "$app_name" "runtime gate: bin/ci"
      run_rails_as_app "$app_name" "$app_dir" \
        "ci" \
        || { deploy_status "$app_name" "runtime gate: bin/ci" "failed"; log_err "bin/ci failed"; return 1; }
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
