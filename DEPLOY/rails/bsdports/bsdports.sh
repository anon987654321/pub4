#!/usr/bin/env zsh
# bsdports.sh — deploys the tracked bsdports Rails tree at app/.
set -euo pipefail

APP_NAME=bsdports
APP_DIR=/home/${APP_NAME}/app
APP_PORT=47312
APP_DOMAIN=bsdports.org
SCRIPT_DIR=${0:a:h}
SRC_DIR=${SCRIPT_DIR}
SHARED_BUNDLE_CACHE=${SHARED_BUNDLE_CACHE:-/var/cache/pub4/bundle/ruby34}

. "${SCRIPT_DIR:h}/shared/deploy/@shared_functions.sh"

need_cmd ruby34 bundle doas

[[ -d $SRC_DIR ]] || { log_err "missing source tree: $SRC_DIR"; exit 1; }

log "${APP_NAME} — deploying tracked tree → ${APP_DIR}"

id "$APP_NAME" >/dev/null 2>&1 || doas useradd -m -L daemon -s /bin/ksh "$APP_NAME"
doas mkdir -p "$APP_DIR"

# Engine-ize: legacy shared copy DEPRECATED (tranche10+). Use bundle + pub4-shared path gem (see Gemfile, WIRING_NOTES). Parametric shared now via engine autoload.
# doas cp -R "${SCRIPT_DIR:h}/shared/bin/." "${APP_DIR}/bin/" 2>/dev/null || true
# doas cp -R "${SCRIPT_DIR:h}/shared/public/." "${APP_DIR}/public/" 2>/dev/null || true
# doas cp -R "${SCRIPT_DIR:h}/shared/config/." "${APP_DIR}/config/" 2>/dev/null || true
# doas cp -R "${SCRIPT_DIR:h}/shared/app/." "${APP_DIR}/app/" 2>/dev/null || true
# doas cp "${SCRIPT_DIR:h}/shared/Rakefile" "${APP_DIR}/Rakefile" 2>/dev/null || true
# doas cp "${SCRIPT_DIR:h}/shared/config.ru" "${APP_DIR}/config.ru" 2>/dev/null || true

# Per-app tracked tree last (specialized instances + custom overrides win)
doas cp -R "${SRC_DIR}/." "${APP_DIR}/"
doas rm -rf "/home/${APP_NAME}/shared"
doas cp -R /home/dev/pub4/DEPLOY/rails/shared "/home/${APP_NAME}/shared"
doas chown -R "${APP_NAME}:${APP_NAME}" "/home/${APP_NAME}/shared"
doas chown -R "${APP_NAME}:${APP_NAME}" "$APP_DIR"
overlay_shared_initializers "$APP_DIR"
doas chown -R "${APP_NAME}:${APP_NAME}" "$APP_DIR"

# Strict rules.yml gate: MASTER scan DEPLOY before bundle (per success_criteria, self_test, evidence_scoring)
if ! master_scan_dep "$APP_NAME"; then
  log "MASTER scan violations — aborting per rules.yml"
  exit 1
fi

cd "$APP_DIR"

typeset bundle_home="/home/${APP_NAME}/.bundle"
doas mkdir -p "$bundle_home"

if [[ ! -d ${bundle_home}/gems ]]; then
  if [[ -d ${SHARED_BUNDLE_CACHE}/gems ]]; then
    log "Bootstrapping gems from ${SHARED_BUNDLE_CACHE}"
    doas cp -R "${SHARED_BUNDLE_CACHE}/gems" "$bundle_home/"
    [[ -d ${SHARED_BUNDLE_CACHE}/cache ]] && doas cp -R "${SHARED_BUNDLE_CACHE}/cache" "$bundle_home/" || true
  else
    log_warn "No shared bundle cache found; bundle install will resolve gems normally"
  fi
  doas chown -R "${APP_NAME}:${APP_NAME}" "$bundle_home"
fi

doas mkdir -p "${APP_DIR}/.bundle"
print -- "---\nBUNDLE_PATH: \"${bundle_home}/gems\"" | doas tee "${APP_DIR}/.bundle/config" >/dev/null
doas chown -R "${APP_NAME}:${APP_NAME}" "${APP_DIR}/.bundle"

doas sh -c "su -m ${APP_NAME} -c 'cd ${APP_DIR} && bundle config set --local frozen false && bundle config set --local deployment true && bundle config set --local without \"development test\" && RAILS_ENV=production bundle install'"
db_create_migrate_as_app "$APP_NAME" "$APP_DIR"
[[ -f ${APP_DIR}/db/seeds.rb ]] && db_seed_as_app "$APP_NAME" "$APP_DIR" || true

install_rcd "$APP_NAME" "$APP_DIR" "$APP_PORT" "$APP_NAME"
[[ -n $APP_DOMAIN ]] && relayd_add_relay "$APP_DOMAIN" "$APP_PORT"

doas rcctl restart "$APP_NAME" || doas rcctl start "$APP_NAME"
log_ok "$APP_NAME live on :$APP_PORT"
