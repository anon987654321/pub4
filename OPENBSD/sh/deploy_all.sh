#!/usr/bin/env zsh
# Workstation orchestrator: sync pub4 to VPS and run OPENBSD/OPERATOR.sh.
#
# Canonical app list: OPERATOR/master.json (active Rails apps).
# NOT deployed (archived installers only)
#   → see OPERATOR/archive/recovery/manifest.json
#
# Usage:
#   zsh OPENBSD/sh/deploy_all.sh
#   VPS_HOST=dev@46.23.89.226 SSH_KEY=~/.ssh/id_ed25519 zsh OPENBSD/sh/deploy_all.sh
#   zsh OPENBSD/sh/deploy_all.sh --per-app   # also run rails/<app>/<app>.sh (copies to /home/<app>/app)
set -euo pipefail

SCRIPT_DIR=${0:a:h}
DEPLOY_ROOT=${SCRIPT_DIR:h}
PUB4_ROOT=${PUB4_ROOT:-${DEPLOY_ROOT:h}}

: "${VPS_HOST:=46.23.89.226}"
: "${VPS_USER:=dev}"
: "${SSH_KEY:=${HOME}/.ssh/id_rsa}"
: "${REMOTE_PUB4:=/home/dev/pub4}"
: "${USE_GIT_PULL:=1}"
: "${REMOTE_RUBY:=ruby34}"
: "${RUN_REMOTE_HEALTH:=1}"
: "${ALLOW_PARTIAL_DEPLOY:=0}"

typeset -a ssh_opts=(-o StrictHostKeyChecking=no -o ConnectTimeout=15)
[[ -f $SSH_KEY ]] && ssh_opts+=(-i "$SSH_KEY")

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" }
error() { log "ERROR: $*"; exit 1 }

vssh() { ssh "${ssh_opts[@]}" "${VPS_USER}@${VPS_HOST}" "$@" }

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
  log "Rsync OPERATOR/ → ${REMOTE_PUB4}/OPERATOR/ ..."
  rsync -az --delete \
    -e "ssh ${(j: :)ssh_opts}" \
    "${DEPLOY_ROOT}/" "${VPS_USER}@${VPS_HOST}:${REMOTE_PUB4}/OPERATOR/" \
    || error "rsync failed"
fi

log "Running OpenBSD deploy stage 2 (services + Rails bootstrap from RAILS trees)..."
if ! vssh "cd ${REMOTE_PUB4}/OPENBSD && doas zsh OPERATOR.sh --stage-2"; then
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

log "Smoke checks..."
vssh 'ps aux | grep -E "falcon serve" | grep -v grep' || log "WARN: no Falcon processes"
if command -v jq >/dev/null 2>&1; then
  while IFS=$'\t' read -r app port; do
    vssh "nc -z 127.0.0.1 ${port}" 2>/dev/null && log "  ${app} listening on :${port}" \
      || log "WARN: ${app} not listening on :${port}"
  done < <(jq -r '.apps[] | [.name, .port] | @tsv' "${DEPLOY_ROOT}/master.json")
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
log "VPS: ssh ${ssh_opts[*]} ${VPS_USER}@${VPS_HOST}"
log "Health: ${REMOTE_RUBY} ${REMOTE_PUB4}/OPENBSD/health_check.rb --public --all-ready-apps (on VPS)"
