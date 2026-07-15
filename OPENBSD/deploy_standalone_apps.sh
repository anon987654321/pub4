#!/usr/bin/env zsh
# Deploy apps listed in OPENBSD/master.json standalone_apps (e.g. BPLAN).
# Run on VPS as dev: zsh OPENBSD/deploy_standalone_apps.sh
set -euo pipefail

SCRIPT_DIR=${0:a:h}
PUB4=${PUB4:-${SCRIPT_DIR:h}}
MASTER_JSON=${MASTER_JSON:-${SCRIPT_DIR}/master.json}

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" }

command -v jq >/dev/null 2>&1 || { log "ERROR: jq required"; exit 1; }
[[ -f $MASTER_JSON ]] || { log "ERROR: missing ${MASTER_JSON}"; exit 1; }

typeset -a names scripts
names=("${(@f)$(jq -r '.standalone_apps[]?.name // empty' "$MASTER_JSON")}")
scripts=("${(@f)$(jq -r '.standalone_apps[]?.deploy_script // empty' "$MASTER_JSON")}")

(( ${#names[@]} > 0 )) || { log "no standalone_apps in master.json"; exit 0; }

log "standalone deploy — ${#names[@]} app(s)"

typeset i name script path
for (( i = 1; i <= ${#names[@]}; i++ )); do
  name=${names[i]}
  script=${scripts[i]}
  path="${PUB4}/${script}"
  log "=== ${name} (${script}) ==="
  [[ -f $path ]] || { log "WARN: missing ${path}"; continue; }
  if ! zsh "$path"; then
    log "WARN: ${name} deploy script failed"
    continue
  fi
  doas rcctl check "$name" 2>/dev/null && log "ok: ${name}" || log "WARN: ${name} rcctl check failed"
  typeset port
  port=$(jq -r --arg n "$name" '.standalone_apps[] | select(.name == $n) | .port' "$MASTER_JSON")
  if [[ -n $port && $port != null ]]; then
    curl -fsS -m 30 "http://127.0.0.1:${port}/up" >/dev/null \
      && log "smoke: ${name} /up ok on :${port}" \
      || log "WARN: ${name} /up failed on :${port}"
  fi
done

log "standalone deploy finished"