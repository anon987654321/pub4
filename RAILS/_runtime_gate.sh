#!/usr/bin/env zsh
set -euo pipefail
# _runtime_gate.sh — MASTER rules scan and the full CI gate (bundle + db:prepare
# + bin/ci) that must pass before a deploy is allowed to restart the service.
# Source this file; do not execute directly. Requires _core.sh sourced first.

# master_scan_dep APP_NAME — rules.yml gate via MASTER CLI (requires bundle exec in MASTER/).
master_scan_dep() {
  local app_name=$1
  local master=${MASTER_ROOT:-/home/dev/pub4/MASTER}
  local log=/tmp/master_${app_name}_scan.log
  [[ -x ${master}/bin/cli ]] || return 0
  [[ -n ${SKIP_MASTER_SCAN:-} ]] && { log "MASTER scan skipped (SKIP_MASTER_SCAN)"; return 0; }
  log "MASTER rules scan (OPERATOR) pre-bundle"
  if ! (cd "$master" && MASTER_SCAN_ONLY=1 MASTER_SAFE_MODE=1 bundle_exec exec ruby bin/cli "/scan OPENBSD") \
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
    deploy_status "$app_name" "runtime gate: bundle install"
    run_rails_as_app "$app_name" "$app_dir" \
      "bundle34 config unset without && bundle34 install --jobs=2" \
      || { deploy_status "$app_name" "runtime gate: bundle install" "failed"; log_err "ci bundle install failed"; return 1; }
    deploy_status "$app_name" "runtime gate: bundle check"
    run_rails_as_app "$app_name" "$app_dir" bundle34 check \
      || { deploy_status "$app_name" "runtime gate: bundle check" "failed"; log_err "bundle check failed"; return 1; }
    deploy_status "$app_name" "runtime gate: db:prepare"
    run_rails_as_app "$app_name" "$app_dir" \
      "SECRET_KEY_BASE=${secret} RAILS_ENV=production bundle34 exec rails db:prepare" \
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
        "SECRET_KEY_BASE=${secret} PUB4_RAILS_ROOT=${rails_tree} RAILS_ENV=test CI=1 PUB4_CI_GUARD=1 bundle34 exec bin/ci" \
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
