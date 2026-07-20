#!/usr/bin/env zsh
set -euo pipefail
# _assets.sh — Propshaft/dartsass asset precompile for copy-tree deploy.
# Source this file; do not execute directly. Requires _core.sh sourced first.

# master_web_assets_precompile — Propshaft digest manifest + digested files for production face UI.
master_web_assets_precompile() {
  local web_root=${1:-${PUB4:-/home/dev/pub4}/MASTER/web}
  [[ -d $web_root ]] || { log_warn "master_web_assets_precompile: missing ${web_root}"; return 0; }
  log "MASTER web assets:precompile"
  (
    cd "$web_root"
    rm -rf public/assets
    RAILS_ENV=production SECRET_KEY_BASE="${SECRET_KEY_BASE:-dummy}" bundle_exec exec rails assets:precompile
    bundle_exec exec ruby "${PUB4:-/home/dev/pub4}/RAILS/master_web_assets_gate.rb"
  ) || { log_err "MASTER web assets precompile failed"; return 1; }
  log_ok "MASTER web assets ready"
}

# rails_assets_precompile_as_app APP_NAME APP_DIR — Propshaft digest manifest for production JS/CSS.
rails_assets_precompile_as_app() {
  local app_name=$1
  local app_dir=$2
  local secret
  secret=$(app_secret_for "$app_name")
  log "assets:precompile for ${app_name}"
  run_rails_as_app "$app_name" "$app_dir" \
    "SECRET_KEY_BASE=${secret} RAILS_ENV=production bundle34 exec rails assets:precompile" \
    || { log_err "assets:precompile failed for ${app_name}"; return 1; }
  log_ok "assets ready for ${app_name}"
}
