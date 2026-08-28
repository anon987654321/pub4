#!/usr/bin/env zsh
# _deploy.sh — orchestrator for the copy-tree deploy pipeline. Sources every
# sibling _*.sh helper file, then exposes deploy_tracked_app as the single
# entry point each app's <app>.sh script calls.
#
# Requires: zsh, ruby34, bundle, rails, doas
set -euo pipefail

typeset _deploy_sh_dir=${${(%):-%x}:A:h}

. "${_deploy_sh_dir}/_core.sh"
. "${_deploy_sh_dir}/_bundle.sh"
. "${_deploy_sh_dir}/_sync.sh"
. "${_deploy_sh_dir}/_scaffold.sh"
. "${_deploy_sh_dir}/_database.sh"
. "${_deploy_sh_dir}/_assets.sh"
. "${_deploy_sh_dir}/_runtime_gate.sh"
. "${_deploy_sh_dir}/_service.sh"

# deploy_tracked_app APP_NAME — copy the app tree, install bundle/db/service, then restart.
deploy_tracked_app() {
  local app_name=${1:-$APP_NAME}

  need_cmd ruby34 bundle doas

  [[ -d $SRC_DIR ]] || { log_err "missing source tree: $SRC_DIR"; exit 1; }

  log "${app_name} — deploying tracked tree → ${APP_DIR}"
  deploy_status "$app_name" "sync tree"

  id "$app_name" >/dev/null 2>&1 || doas useradd -m -L daemon -s /bin/ksh "$app_name"
  doas mkdir -p "$APP_DIR"

  sync_tree "${SRC_DIR}/" "${APP_DIR}"
  doas rm -rf "/home/${app_name}/shared"
  sync_tree "${PUB4_RAILS_ROOT:-/home/dev/pub4/RAILS}/shared" "/home/${app_name}/shared"
  doas chown -R "${app_name}:${app_name}" "/home/${app_name}/shared"
  doas chown -R "${app_name}:${app_name}" "$APP_DIR"
  overlay_shared_initializers "$APP_DIR"
  overlay_shared_public "$APP_DIR"
  # (removed) overlay_brgen_radio_manifest — the function was never defined and the
  # manifest it targeted lives at config/radio_bergen, which the tree sync above
  # already copies. The orphaned call aborted the SKIP_CI deploy path with
  # "command not found". The full-CI path never called it. See ENGINES.md notes.
  doas chown -R "${app_name}:${app_name}" "$APP_DIR"

  deploy_status "$app_name" "master scan"
  if ! master_scan_dep "$app_name"; then
    log "MASTER scan violations — aborting per rules.yml"
    deploy_status "$app_name" "master scan" "failed"
    exit 1
  fi

  cd "$APP_DIR"

  typeset bundle_home="/home/${app_name}/.bundle"
  doas mkdir -p "$bundle_home"

  if [[ ! -d ${bundle_home}/gems ]]; then
  # sync_tree, not a bare openrsync. sync_tree tries openrsync, retries without
  # --delete, and falls back to a tar copy; these four calls had no fallback at
  # all -- so the one operation on this box that is allowed to fail quietly was
  # also the one whose failure leaves an app with no gems. BLOCKERS.md #4 named
  # the asymmetry. The trailing 0 is "do not delete the destination first": a
  # bundle cache is merged into, never replaced.
    if [[ -d ${SHARED_BUNDLE_CACHE}/gems ]]; then
      log "Bootstrapping gems from ${SHARED_BUNDLE_CACHE}"
      doas mkdir -p "${bundle_home}/gems" "${bundle_home}/cache"
      sync_tree "${SHARED_BUNDLE_CACHE}/gems" "${bundle_home}/gems" 0
      [[ -d ${SHARED_BUNDLE_CACHE}/cache ]] && sync_tree "${SHARED_BUNDLE_CACHE}/cache" "${bundle_home}/cache" 0 || true
    elif [[ -d /home/amber/.bundle/gems && ${bundle_home} != /home/amber/.bundle ]]; then
      log "Bootstrapping gems from /home/amber/.bundle"
      doas mkdir -p "${bundle_home}/gems" "${bundle_home}/cache"
      sync_tree /home/amber/.bundle/gems "${bundle_home}/gems" 0
      [[ -d /home/amber/.bundle/cache ]] && sync_tree /home/amber/.bundle/cache "${bundle_home}/cache" 0 || true
    else
      log_warn "No shared bundle cache found; bundle install will resolve gems normally"
    fi
    doas chown -R "${app_name}:${app_name}" "$bundle_home"
  fi

  doas mkdir -p "${APP_DIR}/.bundle"
  print -- "---\nBUNDLE_PATH: \"${bundle_home}/gems\"" | doas tee "${APP_DIR}/.bundle/config" >/dev/null
  doas chown -R "${app_name}:${app_name}" "${APP_DIR}/.bundle"

  deploy_status "$app_name" "bundle install"
  bundle_install_as_app "$APP_NAME" "$APP_DIR"
  log_ok "production bundle installed for ${app_name}"
  migrate_sqlite_db_to_storage_if_needed "$APP_NAME" "$APP_DIR"
  # Stop the running app before touching its SQLite db: db:prepare/migrate hangs
  # indefinitely waiting on the write lock a live Falcon worker already holds,
  # which silently swallowed every deploy's runtime gate (precompile + bin/ci)
  # behind it -- this app_name may not have a running service yet on first deploy.
  doas rcctl stop "$app_name" 2>/dev/null || true
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
  [[ -n $APP_DOMAIN ]] && relayd_add_relay "$APP_DOMAIN" "$APP_PORT"

  rails_runtime_gate "$APP_NAME" "$APP_DIR" || { deploy_status "$app_name" "runtime gate" "failed"; exit 1; }
  if [[ ${DEMO_SEED_ON_DEPLOY:-0} == 1 ]]; then
    deploy_status "$app_name" "demo seed"
    if [[ $app_name == brgen || $app_name == amber ]]; then
      seed_demo_as_app "$APP_NAME" "$APP_DIR"
    fi
  fi
  deploy_status "$app_name" "restart"
  doas rcctl restart "$APP_NAME" || doas rcctl start "$APP_NAME"
  if [[ $app_name == brgen ]]; then
    warm_brgen_after_restart "$APP_PORT"
  fi
  deploy_status "$app_name" "done" "done"
  log_ok "$APP_NAME live on :$APP_PORT"
}
