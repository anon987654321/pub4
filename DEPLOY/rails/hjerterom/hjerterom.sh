#!/usr/bin/env zsh
# hjerterom.sh — deploys tracked Rails tree at app/ as %APP_NAME%
set -euo pipefail

APP_NAME=%APP_NAME%
APP_DIR=/home/${APP_NAME}/app
APP_PORT=38891
APP_DOMAIN=
SCRIPT_DIR=${0:a:h}
SRC_DIR=${SCRIPT_DIR}/app

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle doas

[[ -d $SRC_DIR ]] || { log_err "missing source tree: $SRC_DIR"; exit 1 }

log "${APP_NAME} — deploying tracked tree → ${APP_DIR}"

id "$APP_NAME" >/dev/null 2>&1 || doas useradd -m -L daemon -s /bin/ksh "$APP_NAME"
doas mkdir -p "$APP_DIR"

doas cp -R "${SRC_DIR}/." "${APP_DIR}/"
doas chown -R "${APP_NAME}:${APP_NAME}" "$APP_DIR"

cd "$APP_DIR"

typeset bundle_home="/home/${APP_NAME}/.bundle"
if [[ ! -d ${bundle_home}/gems ]]; then
  log "Bootstrapping gems from amber"
  doas mkdir -p "$bundle_home"
  doas cp -R /home/amber/.bundle/gems "$bundle_home/"
  doas chown -R "${APP_NAME}:${APP_NAME}" "$bundle_home"
fi
print "---\nBUNDLE_PATH: \"${bundle_home}/gems\"" | doas tee "${APP_DIR}/.bundle/config" >/dev/null

doas -u "$APP_NAME" sh -c "cd ${APP_DIR} && RAILS_ENV=production bundle install --deployment --without development:test"
doas -u "$APP_NAME" sh -c "cd ${APP_DIR} && RAILS_ENV=production bin/rails db:create db:migrate"
[[ -f ${APP_DIR}/db/seeds.rb ]] && doas -u "$APP_NAME" sh -c "cd ${APP_DIR} && RAILS_ENV=production bin/rails db:seed" || true

install_rcd "$APP_NAME" "$APP_DIR" "$APP_PORT" "$APP_NAME"
[[ -n $APP_DOMAIN ]] && relayd_add_relay "$APP_DOMAIN" "$APP_PORT"

doas rcctl restart "$APP_NAME" || doas rcctl start "$APP_NAME"
log_ok "$APP_NAME live on :$APP_PORT"
