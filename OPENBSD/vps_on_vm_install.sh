#!/usr/bin/env zsh
# Run on vm23 as dev — MASTER + active Rails apps (scripts must be synced from workstation).
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
ruby "$PUB4/RAILS/gates/runner.rb" master_web_assets
doas rcctl restart master || doas rcctl start master

# `set -euo pipefail` at the top did nothing for the loop below, because every
# fallible step carried its own `|| log WARN` and a logged warning is a zero exit.
# A deploy script that fails three apps and then prints "done" is read as evidence
# that the deploy worked, which is the same defect restore_backups.sh was written
# to stop repeating. Count the failures and let the exit status carry them.
failed=0
APPS=(brgen amber bsdports)
for app in $APPS; do
  log "=== $app ==="
  typeset script="$PUB4/RAILS/${app}/${app}.sh"
  zsh -n "$script" || { log "ERR: syntax error in $script"; failed=$((failed + 1)); continue; }
  zsh "$script" || { log "WARN: $app failed"; failed=$((failed + 1)); }
done

log "=== rcctl ==="
for app in $APPS; do doas rcctl check "$app" 2>/dev/null || true; done
doas rcctl check master 2>/dev/null || true
if (( failed > 0 )); then
  log "FAILED: $failed of ${#APPS} apps — $LOG"
  exit 1
fi
log "done $LOG"
