#!/usr/bin/env zsh
# bplan.sh — deploy BPLAN/rails + content tree (separate from RAILS/apps.yml)
#
# Env (set in /etc/rc.conf.local or before deploy):
#   BPLAN_VIPPS_NUMBER   — Vipps-nummer for betalingsinstruksjoner (Rails payments)
#   BUILD_ID             — optional override; default git short SHA or timestamp
set -euo pipefail

APP_NAME=bplan
APP_DIR=/home/${APP_NAME}/app
CONTENT_DIR=/home/${APP_NAME}/content
APP_PORT=39282
APP_DOMAIN=bplan.pub.healthcare
SCRIPT_DIR=${0:a:h}
SRC_DIR=${SCRIPT_DIR}
BPLAN_ROOT=${SCRIPT_DIR:h}
PUB4_ROOT=${BPLAN_ROOT:h}
RAILS_SHARED=${PUB4_ROOT}/RAILS
SHARED_BUNDLE_CACHE=${SHARED_BUNDLE_CACHE:-/var/cache/pub4/bundle/ruby34}
DEPLOYIGNORE=${BPLAN_ROOT}/.deployignore

. "${RAILS_SHARED}/@core.sh"
. "${RAILS_SHARED}/@bundle.sh"
. "${RAILS_SHARED}/@sync.sh"
. "${RAILS_SHARED}/@assets.sh"
. "${RAILS_SHARED}/@runtime_gate.sh"
. "${RAILS_SHARED}/@service.sh"

log "${APP_NAME} — deploying BPLAN (rails + content)"

need_cmd ruby34 bundle doas

[[ -d $SRC_DIR ]] || { log_err "missing rails tree: $SRC_DIR"; exit 1; }
[[ -d $BPLAN_ROOT ]] || { log_err "missing content root: $BPLAN_ROOT"; exit 1; }

typeset -a tar_excludes=(--exclude rails --exclude .git --exclude vendor)
if [[ -f $DEPLOYIGNORE ]]; then
  while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    tar_excludes+=(--exclude "$line")
  done <"$DEPLOYIGNORE"
  log "using .deployignore ($((${#tar_excludes[@]} - 3)) patterns)"
fi

typeset build_id=${BUILD_ID:-}
if [[ -z $build_id ]]; then
  build_id=$(git -C "$PUB4_ROOT" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)
fi
[[ -n $build_id ]] || { log_err "BUILD_ID empty — set BUILD_ID or deploy from git checkout"; exit 1; }

if [[ -f ${APP_DIR}/BUILD_ID ]]; then
  typeset remote_id
  remote_id=$(doas cat "${APP_DIR}/BUILD_ID" 2>/dev/null || true)
  if [[ $remote_id == $build_id ]]; then
    log_warn "BUILD_ID unchanged ($build_id) — continuing deploy"
  else
    log "BUILD_ID ${remote_id:-∅} → ${build_id}"
  fi
fi

if [[ -z ${BPLAN_VIPPS_NUMBER:-} ]]; then
  log_warn "BPLAN_VIPPS_NUMBER unset — Vipps payment pages show placeholder"
fi

id "$APP_NAME" >/dev/null 2>&1 || doas useradd -m -L daemon -s /bin/ksh "$APP_NAME"
doas mkdir -p "$APP_DIR" "$CONTENT_DIR"

sync_tree "${SRC_DIR}/" "${APP_DIR}"
print -- "$build_id" | doas tee "${APP_DIR}/BUILD_ID" >/dev/null

(cd "$BPLAN_ROOT" && tar cf - "${tar_excludes[@]}" .) | doas sh -c "cd '${CONTENT_DIR}' && tar xf -"
print -- "$build_id" | doas tee "${CONTENT_DIR}/BUILD_ID" >/dev/null

doas rm -f "${APP_DIR}/public/content"
doas ln -sfn "${CONTENT_DIR}" "${APP_DIR}/public/content"
# After `ruby build_plans.rb` in BPLAN/: copy or symlink robots.txt + sitemap.xml
# from ${CONTENT_DIR} into ${APP_DIR}/public/ (Rails also serves them via RobotsController/SitemapsController).
doas chown -h "${APP_NAME}:${APP_NAME}" "${APP_DIR}/public/content"
doas chown -R "${APP_NAME}:${APP_NAME}" "$APP_DIR" "$CONTENT_DIR"

cd "$APP_DIR"

typeset bundle_home="/home/${APP_NAME}/.bundle"
doas mkdir -p "$bundle_home" "${APP_DIR}/.bundle"
print -- "---\nBUNDLE_PATH: \"${bundle_home}/gems\"" | doas tee "${APP_DIR}/.bundle/config" >/dev/null
doas chown -R "${APP_NAME}:${APP_NAME}" "${APP_DIR}/.bundle" "$bundle_home"

bundle_install_as_app "$APP_NAME" "$APP_DIR"
log_ok "production bundle installed for ${APP_NAME}"

doas rcctl stop "$APP_NAME" 2>/dev/null || true
rails_assets_precompile_as_app "$APP_NAME" "$APP_DIR" || true

install_rcd "$APP_NAME" "$APP_DIR" "$APP_PORT" "$APP_NAME"
[[ -n $APP_DOMAIN ]] && relayd_add_relay "$APP_DOMAIN" "$APP_PORT"

rails_runtime_gate "$APP_NAME" "$APP_DIR" || exit 1
doas rcctl restart "$APP_NAME" || doas rcctl start "$APP_NAME"
log_ok "${APP_NAME} live on :${APP_PORT} (${APP_DOMAIN}) BUILD_ID=${build_id}"