#!/usr/bin/env zsh
# amber.sh — deploys the tracked Amber Rails tree at app/.
set -euo pipefail

APP_NAME=amber
APP_DIR=/home/${APP_NAME}/app
APP_PORT=61352
APP_DOMAIN=amber.brgen.no
SCRIPT_DIR=${0:a:h}
SRC_DIR=${SCRIPT_DIR}
SHARED_BUNDLE_CACHE=${SHARED_BUNDLE_CACHE:-/var/cache/pub4/bundle/ruby34}

. "${SCRIPT_DIR:h}/shared/deploy/@shared_functions.sh"

need_cmd ruby34 bundle doas

[[ -d $SRC_DIR ]] || { log_err "missing source tree: $SRC_DIR"; exit 1; }

log "${APP_NAME} — deploying tracked tree → ${APP_DIR}"

id "$APP_NAME" >/dev/null 2>&1 || doas useradd -m -L daemon -s /bin/ksh "$APP_NAME"
doas mkdir -p "$APP_DIR"

doas cp -R "${SRC_DIR}/." "${APP_DIR}/"
doas cp -R "${SCRIPT_DIR:h}/shared/bin/." "${APP_DIR}/bin/" 2>/dev/null || true
doas cp -R "${SCRIPT_DIR:h}/shared/public/." "${APP_DIR}/public/" 2>/dev/null || true
doas cp -R "${SCRIPT_DIR:h}/shared/config/." "${APP_DIR}/config/" 2>/dev/null || true
doas chown -R "${APP_NAME}:${APP_NAME}" "$APP_DIR"

cd "$APP_DIR"

typeset bundle_home="/home/${APP_NAME}/.bundle"
doas mkdir -p "$bundle_home"

if [[ ! -d ${bundle_home}/gems ]]; then
  if [[ -d ${SHARED_BUNDLE_CACHE}/gems ]]; then
    log "Bootstrapping gems from ${SHARED_BUNDLE_CACHE}"
    doas cp -R "${SHARED_BUNDLE_CACHE}/gems" "$bundle_home/"
    [[ -d ${SHARED_BUNDLE_CACHE}/cache ]] && doas cp -R "${SHARED_BUNDLE_CACHE}/cache" "$bundle_home/" || true
  elif [[ -d /home/amber/.bundle/gems && ${bundle_home} != /home/amber/.bundle ]]; then
    log "Bootstrapping gems from /home/amber/.bundle"
    doas cp -R /home/amber/.bundle/gems "$bundle_home/"
    [[ -d /home/amber/.bundle/cache ]] && doas cp -R /home/amber/.bundle/cache "$bundle_home/" || true
  else
    log_warn "No shared bundle cache found; bundle install will resolve gems normally"
  fi
  doas chown -R "${APP_NAME}:${APP_NAME}" "$bundle_home"
fi

doas mkdir -p "${APP_DIR}/.bundle"
print -- "---\nBUNDLE_PATH: \"${bundle_home}/gems\"" | doas tee "${APP_DIR}/.bundle/config" >/dev/null
doas chown -R "${APP_NAME}:${APP_NAME}" "${APP_DIR}/.bundle"

doas -u "$APP_NAME" sh -c "cd ${APP_DIR} && bundle config set --local deployment true && bundle config set --local without 'development test' && RAILS_ENV=production bundle install"
doas -u "$APP_NAME" sh -c "cd ${APP_DIR} && RAILS_ENV=production bin/rails db:create db:migrate"
[[ -f ${APP_DIR}/db/seeds.rb ]] && doas -u "$APP_NAME" sh -c "cd ${APP_DIR} && RAILS_ENV=production bin/rails db:seed" || true

install_rcd "$APP_NAME" "$APP_DIR" "$APP_PORT" "$APP_NAME"
[[ -n $APP_DOMAIN ]] && relayd_add_relay "$APP_DOMAIN" "$APP_PORT"

doas rcctl restart "$APP_NAME" || doas rcctl start "$APP_NAME"
log_ok "$APP_NAME live on :$APP_PORT"
