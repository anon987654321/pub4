#!/usr/bin/env zsh
# _deploy.sh — orchestrator for the copy-tree deploy pipeline. Sources every
# sibling _*.sh helper file, then exposes deploy_tracked_app as the single
# entry point each app's <app>.sh script calls.
#
# Requires: zsh, a Ruby and bundler (OPENBSD/lib/ruby_select.sh picks them), rails, doas
set -euo pipefail

typeset _deploy_sh_dir=${${(%):-%x}:A:h}

. "${_deploy_sh_dir:h}/OPENBSD/lib/ruby_select.sh"

. "${_deploy_sh_dir}/_core.sh"
. "${_deploy_sh_dir}/_bundle.sh"
. "${_deploy_sh_dir}/_sync.sh"
. "${_deploy_sh_dir}/_database.sh"
. "${_deploy_sh_dir}/_assets.sh"
. "${_deploy_sh_dir}/_runtime_check.sh"
. "${_deploy_sh_dir}/_service.sh"

# deploy_tracked_app APP_NAME — copy the app tree, install bundle/db/service, then restart.
deploy_tracked_app() {
  local app_name=${1:-$APP_NAME}
  case "$app_name" in
    brgen|amber|bsdports) ;;
    *) log_err "deploy_tracked_app: refused unknown app: $app_name"; return 2 ;;
  esac

  need_cmd "$RUBY" "$BUNDLE" doas

  [[ -x /usr/local/sbin/pub4-admin ]] || {
    log_err "pub4-admin is missing; run OPERATOR.sh before deploying"
    return 1
  }
  [[ -d $SRC_DIR ]] || { log_err "missing source tree: $SRC_DIR"; exit 1; }

  log "${app_name} — deploying tracked tree → ${APP_DIR}"
  deploy_status "$app_name" "sync tree"
  ${_PRIV} /usr/local/sbin/pub4-admin ensure-app "$app_name" || {
    log_err "app account/layout preparation failed for $app_name"
    return 1
  }

  # Group access to the checkout is needed even on SKIP_CI deployments.
  # Ensure the app is in _pub4ci before the app-user sync traverses /home/dev/pub4.
  ${_PRIV} /usr/local/sbin/pub4-admin ci-prepare "$app_name" || {
    log_err "app checkout access preparation failed for $app_name"
    return 1
  }

  rails_sync_app_tree "$app_name" app
  rails_sync_app_tree "$app_name" shared
  if [[ $app_name == brgen ]]; then
    rails_sync_app_tree "$app_name" verticals
  fi
  overlay_shared_initializers "$APP_DIR"
  overlay_shared_public "$APP_DIR"
  # The app-user sync preserves log, storage and compiled public/assets in the
  # staged replacement. No root chown of checkout-owned tree content is needed.

  deploy_status "$app_name" "master scan"
  if ! master_scan_dep "$app_name"; then
    log "MASTER scan violations — aborting per laws.yml"
    deploy_status "$app_name" "master scan" "failed"
    exit 1
  fi

  cd "$APP_DIR"

  run_rails_as_app "$app_name" "$APP_DIR" "bundle-cache-prepare" || {
    log_err "bundle cache preparation failed for $app_name"
    return 1
  }

  deploy_status "$app_name" "bundle install"
  bundle_install_as_app "$APP_NAME" "$APP_DIR"
  log_ok "production bundle installed for ${app_name}"
  migrate_sqlite_db_to_storage_if_needed "$APP_NAME" "$APP_DIR"
  # Stop the running app before touching its SQLite db: db:prepare/migrate hangs
  # indefinitely waiting on the write lock a live Falcon worker already holds,
  # which silently swallowed every deploy's runtime check (precompile + bin/ci)
  # behind it -- this app_name may not have a running service yet on first deploy.
  pub4_rcctl stop "$app_name" 2>/dev/null || true
  deploy_status "$app_name" "db migrate"
  db_create_migrate_as_app "$APP_NAME" "$APP_DIR" || { deploy_status "$app_name" "db migrate" "failed"; exit 1; }
  log_ok "database migrated for ${app_name}"
  if [[ ${RUN_PRODUCTION_SEEDS:-} == 1 && ${SEED_ON_DEPLOY:-} != 1 ]]; then
    SEED_ON_DEPLOY=1
  fi
  if [[ -f ${APP_DIR}/db/seeds.rb && ${SEED_ON_DEPLOY:-} == 1 ]]; then
    db_seed_as_app "$APP_NAME" "$APP_DIR"
  fi

  install_rcd "$APP_NAME" "$APP_DIR" "$APP_PORT" "$APP_NAME"
  [[ -n $APP_DOMAIN ]] && relayd_add_relay "$APP_NAME" "$APP_DOMAIN" "$APP_PORT"

  rails_runtime_check "$APP_NAME" "$APP_DIR" || { deploy_status "$app_name" "runtime check" "failed"; exit 1; }
  if [[ ${DEMO_SEED_ON_DEPLOY:-0} == 1 ]]; then
    deploy_status "$app_name" "demo seed"
    if [[ $app_name == brgen || $app_name == amber ]]; then
      seed_demo_as_app "$APP_NAME" "$APP_DIR"
    fi
  fi
  deploy_status "$app_name" "restart"
  pub4_rcctl restart "$APP_NAME" || pub4_rcctl start "$APP_NAME"
  if [[ $app_name == brgen ]]; then
    warm_brgen_after_restart "$APP_PORT"
  fi
  deploy_status "$app_name" "done" "done"
  log_ok "$APP_NAME live on :$APP_PORT"
}
