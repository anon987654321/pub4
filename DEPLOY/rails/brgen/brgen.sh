#!/usr/bin/env zsh
# brgen.sh — Brgen social network (Rails 8). Deploys the tracked tree at app/.
set -euo pipefail

APP_NAME=brgen
APP_DIR=/home/${APP_NAME}/app
APP_PORT=38182
SCRIPT_DIR=${0:a:h}
SRC_DIR=${SCRIPT_DIR}/app

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle doas

[[ -d $SRC_DIR ]] || { log_err "missing source tree: $SRC_DIR"; exit 1; }

log "Brgen — deploying tracked tree → ${APP_DIR}"

# ── User + dirs ────────────────────────────────────────────────────────────
id "$APP_NAME" >/dev/null 2>&1 || doas useradd -m -L daemon -s /bin/ksh "$APP_NAME"
doas mkdir -p "$APP_DIR"

# ── Sync tree ──────────────────────────────────────────────────────────────
doas cp -R "${SRC_DIR}/." "${APP_DIR}/"
doas chown -R "${APP_NAME}:${APP_NAME}" "$APP_DIR"

cd "$APP_DIR"

# ── Bundle path inherits from sibling app to avoid OOM on first install ────
typeset bundle_home="/home/${APP_NAME}/.bundle"
if [[ ! -d ${bundle_home}/gems ]]; then
  log "Bootstrapping gems from amber"
  doas mkdir -p "$bundle_home"
  doas cp -R /home/amber/.bundle/gems "$bundle_home/"
  doas chown -R "${APP_NAME}:${APP_NAME}" "$bundle_home"
fi
print -- "---\nBUNDLE_PATH: \"${bundle_home}/gems\"" | doas tee "${APP_DIR}/.bundle/config" >/dev/null

# ── Install + migrate + seed ───────────────────────────────────────────────
doas -u "$APP_NAME" sh -c "cd ${APP_DIR} && RAILS_ENV=production bundle install --deployment --without development:test"
doas -u "$APP_NAME" sh -c "cd ${APP_DIR} && RAILS_ENV=production bin/rails db:create db:migrate"
[[ -f ${APP_DIR}/db/seeds.rb ]] && doas -u "$APP_NAME" sh -c "cd ${APP_DIR} && RAILS_ENV=production bin/rails db:seed" || true

# ── Service + relay ────────────────────────────────────────────────────────
install_rcd "$APP_NAME" "$APP_DIR" "$APP_PORT" "$APP_NAME"
relayd_add_relay "${APP_NAME}.no" "$APP_PORT"

doas rcctl restart "$APP_NAME" || doas rcctl start "$APP_NAME"
log_ok "$APP_NAME live on :$APP_PORT"
