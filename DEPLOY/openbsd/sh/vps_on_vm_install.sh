#!/usr/bin/env zsh
# Run on vm23 as dev — MASTER + 6 Rails apps (scripts must be synced from workstation).
set -euo pipefail
PUB4=/home/dev/pub4
LOG=/tmp/pub4_on_vm_install_$(date +%Y%m%d_%H%M%S).log
exec > >(tee -a "$LOG") 2>&1
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" }

log "MASTER bundle"
cd "$PUB4/MASTER" && bundle install
cd "$PUB4/MASTER/web" && bundle config set --local without 'development test' \
  && RAILS_ENV=production bundle install
cd "$PUB4/MASTER/web" && RAILS_ENV=production SECRET_KEY_BASE="${SECRET_KEY_BASE:-dummy}" bundle exec rails assets:precompile
ruby "$PUB4/DEPLOY/rails/master_web_assets_gate.rb"
doas rcctl restart master || doas rcctl start master

APPS=(brgen amber bsdports hjerterom)
for app in $APPS; do
  log "=== $app ==="
  typeset script="$PUB4/DEPLOY/rails/${app}/${app}.sh"
  zsh -n "$script" || { log "ERR: syntax error in $script"; continue; }
  zsh "$script" || log "WARN: $app failed"
done

log "=== rcctl ==="
for app in $APPS; do doas rcctl check "$app" 2>/dev/null || true; done
doas rcctl check master 2>/dev/null || true
log "done $LOG"