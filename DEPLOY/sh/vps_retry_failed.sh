#!/usr/bin/env zsh
# Run on vm23 — redeploy apps that failed in a prior install pass.
set -euo pipefail
PUB4=/home/dev/pub4
LOG=/tmp/pub4_retry_failed_$(date +%Y%m%d_%H%M%S).log
exec > >(tee -a "$LOG") 2>&1
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" }

export SKIP_MASTER_SCAN=1
APPS=(brgen amber blognet hjerterom)

for app in $APPS; do
  log "=== retry ${app} ==="
  typeset script="$PUB4/DEPLOY/rails/${app}/${app}.sh"
  if zsh "$script"; then
    doas rcctl check "$app" 2>/dev/null && log "ok: ${app}" || log "WARN: ${app} rcctl check failed"
  else
    log "WARN: ${app} deploy failed"
  fi
done

log "=== summary ==="
for app in brgen amber blognet bsdports baibl hjerterom; do
  printf '  %s: ' "$app"
  doas rcctl check "$app" 2>/dev/null || print "not running"
done
doas rcctl check master 2>/dev/null || true
log "done $LOG"