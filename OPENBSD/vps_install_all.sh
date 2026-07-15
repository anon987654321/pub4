#!/usr/bin/env zsh
# Run ON the VPS (vm23) as dev — installs MASTER web + each Rails app deploy script.
set -euo pipefail

PUB4=${PUB4:-/home/dev/pub4}
LOG=${LOG:-/tmp/pub4_install_$(date +%Y%m%d_%H%M%S).log}

exec > >(tee -a "$LOG") 2>&1

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" }

log "pub4 install — log: $LOG"
log "free memory: $(vmstat -s | awk '/free memory/{print $1, $2}')"

if [[ -d ${PUB4}/.git ]]; then
  log "git pull"
  git -C "$PUB4" stash push -m "auto-before-install-$(date +%Y%m%d)" -u 2>/dev/null || true
  git -C "$PUB4" pull origin main || log "WARN: git pull failed (continuing with tree on disk)"
  git -C "$PUB4" log -1 --oneline
fi

log "=== MASTER CLI + web ==="
[[ -d ${PUB4}/MASTER ]] || { log "ERR: MASTER missing"; exit 1 }
cd "${PUB4}/MASTER"
bundle install
cd "${PUB4}/MASTER/web"
bundle config set --local path vendor/bundle
bundle install
RAILS_ENV=production SECRET_KEY_BASE="${SECRET_KEY_BASE:-dummy}" bundle exec rails assets:precompile
bundle exec ruby "${PUB4}/RAILS/master_web_assets_gate.rb"
doas rcctl restart master 2>/dev/null || doas rcctl start master
doas rcctl check master || log "WARN: master not ok"

typeset -a APPS
if command -v jq >/dev/null 2>&1 && [[ -f ${PUB4}/OPENBSD/master.json ]]; then
  APPS=("${(@f)$(jq -r '.apps[].name' "${PUB4}/OPENBSD/master.json")}")
else
  APPS=(brgen amber bsdports)
fi

for app in $APPS; do
  typeset script="${PUB4}/RAILS/${app}/${app}.sh"
  log "=== Rails: ${app} ==="
  if [[ ! -f $script ]]; then
    log "WARN: missing $script"
    continue
  fi
  # Scripts call doas internally; do not wrap in doas (nested doas → "Operation not permitted").
  if ! zsh "$script"; then
    log "WARN: ${app} deploy script failed"
  else
    doas rcctl check "$app" 2>/dev/null && log "ok: ${app}" || log "WARN: ${app} check failed"
  fi
done

if [[ -f ${PUB4}/OPENBSD/deploy_standalone_apps.sh ]]; then
  log "=== Standalone apps (BPLAN, etc.) ==="
  zsh "${PUB4}/OPENBSD/deploy_standalone_apps.sh" || log "WARN: standalone deploy failed"
fi

log "=== summary ==="
for app in $APPS; do
  printf '  %s: ' "$app"
  doas rcctl check "$app" 2>/dev/null || print "not running"
done
doas rcctl check master 2>/dev/null || true
log "finished — $LOG"