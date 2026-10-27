#!/usr/bin/env zsh
set -euo pipefail
# _runtime_check.sh — MASTER rules scan and the full CI check (bundle + db:prepare
# + bin/ci) that must pass before a deploy is allowed to restart the service.
# Source this file; do not execute directly. Requires _core.sh sourced first.

# master_scan_dep APP_NAME — laws.yml check via MASTER CLI (requires bundle exec in MASTER/).
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
  [[ -x ${master}/bin/master ]] || { log_err "MASTER scan unavailable at ${master}"; return 1; }
  mkdir -p "$log_dir" || { log_err "cannot create ${log_dir} for MASTER scan log"; return 1; }
  chmod 700 "$log_dir"
  log "MASTER rules scan (OPERATOR) pre-bundle"
  if ! (cd "$master" && MASTER_SCAN_DETERMINISTIC=1 MASTER_SAFE_MODE=1 bundle_exec exec ruby bin/check --scan-only --tree=RAILS) \
    </dev/null >"$log" 2>&1; then
    cat "$log" >&2
    log_err "MASTER scan CLI failed"
    return 1
  fi
  cat "$log" >&2
  if grep -Eq '[1-9][0-9]* total violations|scan[0-9]*: .*([1-9][0-9]*) violations' "$log"; then
    log_err "MASTER scan found violations (evidence_scoring scan_clean check)"
    return 1
  fi
  log_ok "MASTER scan clean"
}

# run_rails_as_app APP_NAME APP_DIR CMD — app-owned bundle/rails (avoids Gemfile.lock permission errors).
run_rails_as_app() {
  local app_name=$1 app_dir=$2 task=${3:-} database=${4:-}
  case "$app_name" in master|brgen|amber|bsdports) ;; *) log_err "run_rails_as_app: refused app: $app_name"; return 2 ;; esac
  [[ $app_dir == "/home/${app_name}/app" ]] || { log_err "run_rails_as_app: refused app path: $app_dir"; return 2; }
  case "$task" in
    bundle-install|ci-bundle-install|bundle-check|bundle-cache-prepare|db-storage-migrate|db-prepare|db-seed|demo-seed|assets-precompile|ci|overlay-initializers|overlay-public) [[ -z $database ]] || return 2 ;;
    schema-load|secondary-db-check) [[ $database == cache || $database == queue || $database == cable ]] || return 2 ;;
    bundle-cas-hydrate)
      [[ $database == ruby[0-9][0-9] || $database == ruby[0-9].[0-9] ]] || return 2 ;;
    *) log_err "run_rails_as_app: refused task: $task"; return 2 ;;
  esac
  [[ $task != demo-seed || $app_name == brgen || $app_name == amber ]] || return 2

  [[ -x /usr/local/sbin/pub4-admin ]] || {
    log_err "run_rails_as_app: pub4-admin is missing; run OPERATOR.sh before deploying"
    return 1
  }
  if [[ $task == schema-load || $task == secondary-db-check || $task == bundle-cas-hydrate ]]; then
    ${_PRIV} /usr/local/sbin/pub4-admin rails-task "$app_name" "$task" "$database"
  else
    ${_PRIV} /usr/local/sbin/pub4-admin rails-task "$app_name" "$task"
  fi
}

# rails_runtime_check APP_NAME APP_DIR — bundle check + db:prepare + bin/ci + master scan before rcctl restart.
rails_runtime_check() {
  local app_name=${1:-}
  local app_dir=${2:-$1}
  [[ -d $app_dir ]] || {
    log_err "rails_runtime_check: missing ${app_dir}"
    return 1
  }
  if [[ ${SKIP_RUNTIME_CHECK:-} == 1 ]]; then
    if [[ ${I_UNDERSTAND_FAST_DEPLOY:-0} != 1 ]]; then
      log_err "runtime check skip requires I_UNDERSTAND_FAST_DEPLOY=1"
      return 1
    fi
    log_warn "runtime check skipped by explicit fast-deploy acknowledgement"
    return 0
  fi
  if [[ -n $app_name ]]; then
    master_scan_dep "$app_name" || { log_err "MASTER scan failed"; return 1; }
  fi
  log "runtime check: ci bundle + db:prepare + bin/ci"
  if [[ -n $app_name ]]; then
    deploy_status "$app_name" "runtime check: bundle install"
    run_rails_as_app "$app_name" "$app_dir" \
      "ci-bundle-install" \
      || { deploy_status "$app_name" "runtime check: bundle install" "failed"; log_err "ci bundle install failed"; return 1; }
    deploy_status "$app_name" "runtime check: bundle check"
    run_rails_as_app "$app_name" "$app_dir" "bundle-check" \
      || { deploy_status "$app_name" "runtime check: bundle check" "failed"; log_err "bundle check failed"; return 1; }
    deploy_status "$app_name" "runtime check: db:prepare"
    run_rails_as_app "$app_name" "$app_dir" \
      "db-prepare" \
      || { deploy_status "$app_name" "runtime check: db:prepare" "failed"; log_err "db:prepare failed"; return 1; }
    deploy_status "$app_name" "runtime check: secondary dbs"
    rails_prepare_secondary_dbs_as_app "$app_name" "$app_dir" \
      || { deploy_status "$app_name" "runtime check: secondary dbs" "failed"; return 1; }
    deploy_status "$app_name" "runtime check: assets precompile"
    rails_assets_precompile_as_app "$app_name" "$app_dir" \
      || { deploy_status "$app_name" "runtime check: assets precompile" "failed"; return 1; }
    [[ -x ${app_dir}/bin/ci ]] || {
      deploy_status "$app_name" "runtime check: bin/ci" "failed"
      log_err "runtime check: missing executable ${app_dir}/bin/ci"
      return 1
    }
    local rails_tree=${PUB4_RAILS_ROOT:-/home/dev/pub4/RAILS}
    if [[ -d $rails_tree ]]; then
      # traversal is group-based (710 dev:_pub4ci) — vps_ci.sh converges it;
      # this check must not widen /home/dev to the world.
      chmod -R u+rX,g+rX "$rails_tree" 2>/dev/null || true
    fi
    deploy_status "$app_name" "runtime check: bin/ci"
    run_rails_as_app "$app_name" "$app_dir" \
      "ci" \
      || { deploy_status "$app_name" "runtime check: bin/ci" "failed"; log_err "bin/ci failed"; return 1; }
  else
    (cd "$app_dir" && bundle_exec check) || { log_err "bundle check failed"; return 1; }
    (cd "$app_dir" && RAILS_ENV=production bundle_exec exec rails db:prepare) \
      || { log_err "db:prepare failed"; return 1; }
    [[ -x ${app_dir}/bin/ci ]] || {
      log_err "runtime check: missing executable ${app_dir}/bin/ci"
      return 1
    }
    (cd "$app_dir" && bundle_exec exec bin/ci) || { log_err "bin/ci failed"; return 1; }
  fi
  log_ok "runtime check passed"
}
