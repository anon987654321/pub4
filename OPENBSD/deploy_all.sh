#!/usr/bin/env zsh
# Workstation orchestrator: sync pub4 to VPS and run OPENBSD/OPERATOR.sh.
#
# Canonical app list: OPENBSD/master.json (active Rails apps).
# NOT deployed (archived installers only)
#   → see OPENBSD/archive/recovery/manifest.json
#
# Usage:
#   zsh OPENBSD/deploy_all.sh
#   VPS_HOST=dev@46.23.89.226 SSH_KEY=~/.ssh/id_ed25519 zsh OPENBSD/deploy_all.sh
#   zsh OPENBSD/deploy_all.sh --per-app   # also run rails/<app>/<app>.sh (copies to /home/<app>/app)
set -euo pipefail

SCRIPT_DIR=${0:a:h}
DEPLOY_ROOT=${SCRIPT_DIR:h}
PUB4_ROOT=${PUB4_ROOT:-${DEPLOY_ROOT:h:h}}

: "${VPS_HOST:=46.23.89.226}"
: "${VPS_USER:=dev}"
: "${SSH_KEY:=${HOME}/.ssh/id_rsa}"
: "${REMOTE_PUB4:=/home/dev/pub4}"
: "${USE_GIT_PULL:=1}"
: "${REMOTE_RUBY:=ruby34}"
: "${RUN_REMOTE_HEALTH:=1}"
: "${ALLOW_PARTIAL_DEPLOY:=0}"

source "${SCRIPT_DIR}/lib/ssh_vm23.sh"
SSH_HOST=$VPS_HOST
SSH_USER=$VPS_USER

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" }
error() { log "ERROR: $*"; exit 1 }

vssh() { vm23_ssh "$@" }

typeset run_per_app=0
[[ ${1:-} == --per-app ]] && run_per_app=1

typeset -a APPS
if command -v jq >/dev/null 2>&1 && [[ -f ${DEPLOY_ROOT}/master.json ]]; then
  APPS=("${(@f)$(jq -r '.apps[].name' "${DEPLOY_ROOT}/master.json")}")
else
  APPS=(brgen amber bsdports)
fi

log "pub4 deploy — ${#APPS[@]} apps from master.json"
log "Archived (not in this run): see archive/recovery"

log "Testing VPS connectivity..."
vssh 'uname -a' || error "Cannot connect to ${VPS_USER}@${VPS_HOST}"

if [[ $USE_GIT_PULL == 1 ]]; then
  log "Git pull on VPS at ${REMOTE_PUB4}..."
  vssh "test -d ${REMOTE_PUB4}/.git" || error "Clone pub4 on VPS first: git clone https://github.com/anon987654321/pub4.git ${REMOTE_PUB4}"
  vssh "cd ${REMOTE_PUB4} && git pull origin main"
else
  command -v rsync >/dev/null 2>&1 || error "rsync required when USE_GIT_PULL=0"
  log "Rsync OPENBSD/ → ${REMOTE_PUB4}/OPENBSD/ ..."
  rsync -az --delete \
    -e "ssh ${(j: :)VM23_SSH_OPTS}" \
    "${DEPLOY_ROOT}/" "${SSH_USER}@${SSH_HOST}:${REMOTE_PUB4}/OPENBSD/" \
    || error "rsync failed"
fi

log "Running OpenBSD deploy stage 2 (services + Rails bootstrap from RAILS trees)..."
if ! vssh "cd ${REMOTE_PUB4} && doas zsh OPENBSD/OPERATOR.sh --stage-2"; then
  if [[ $ALLOW_PARTIAL_DEPLOY == 1 ]]; then
    log "WARN: OPERATOR.sh reported issues — ALLOW_PARTIAL_DEPLOY=1 set"
  else
    error "OPERATOR.sh failed — refusing false-green deploy"
  fi
fi

if (( run_per_app )); then
  log "Optional per-app deploy scripts (/home/<app>/app layout)..."
  for app in $APPS; do
    typeset script="${REMOTE_PUB4}/RAILS/${app}/${app}.sh"
    log "  ${app}..."
    vssh "test -f ${script}" || { log "WARN: missing ${script}"; continue; }
    vssh "doas zsh ${script} 2>&1 | tee /tmp/${app}_deploy.log" \
      || log "WARN: ${app} — see /tmp/${app}_deploy.log"
  done
fi

if command -v jq >/dev/null 2>&1 && [[ -f ${DEPLOY_ROOT}/master.json ]]; then
  typeset -a STANDALONE
  STANDALONE=("${(@f)$(jq -r '.standalone_apps[]?.name // empty' "${DEPLOY_ROOT}/master.json")}")
  if (( ${#STANDALONE[@]} > 0 )); then
    log "Standalone apps (master.json standalone_apps)..."
    vssh "cd ${REMOTE_PUB4} && zsh OPENBSD/deploy_standalone_apps.sh 2>&1 | tee /tmp/standalone_deploy.log" \
      || log "WARN: standalone deploy — see /tmp/standalone_deploy.log"
  fi
fi

log "Smoke checks..."
vssh 'ps aux | grep -E "falcon serve" | grep -v grep' || log "WARN: no Falcon processes"
if command -v jq >/dev/null 2>&1; then
  while IFS=$'\t' read -r app port; do
    vssh "nc -z 127.0.0.1 ${port}" 2>/dev/null && log "  ${app} listening on :${port}" \
      || log "WARN: ${app} not listening on :${port}"
  done < <(jq -r '(.apps[]?, .standalone_apps[]?) | [.name, .port] | @tsv' "${DEPLOY_ROOT}/master.json")
fi

if [[ $RUN_REMOTE_HEALTH == 1 ]]; then
  log "Authoritative remote health gate..."
  if ! vssh "cd ${REMOTE_PUB4} && ${REMOTE_RUBY} OPENBSD/health_check.rb --public --all-ready-apps"; then
    [[ $ALLOW_PARTIAL_DEPLOY == 1 ]] \
      && log "WARN: remote health failed — ALLOW_PARTIAL_DEPLOY=1 set" \
      || error "remote health failed"
  fi
fi

log "Deploy finished."
log "VPS: ssh ${VM23_SSH_OPTS[*]} ${SSH_USER}@${SSH_HOST}"
log "Health: ${REMOTE_RUBY} ${REMOTE_PUB4}/OPENBSD/health_check.rb --public --all-ready-apps (on VPS)"
