#!/usr/bin/env zsh
# _core.sh — privilege detection, logging, and the one command-existence
# check every other _*.sh file in this directory depends on.
# Source this file; do not execute directly.
set -euo pipefail

PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"

if command -v doas >/dev/null 2>&1; then
  _PRIV=doas
else
  _PRIV=sudo
fi

: "${APP_PORT:=3000}"

log()      { print -P "%F{cyan}==>%f $*"; }
log_ok()   { print -P "%F{green}ok%f $*"; }
log_warn() { print -P "%F{yellow}WARN%f $*" >&2; }
log_err()  { print -P "%F{red}ERR%f $*" >&2; }

need_cmd() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || { log_err "Required: $cmd"; exit 1; }
    log_ok "$cmd found"
  done
}

# pub4_rcctl ACTION SERVICE — fixed broker only. Deploy entrypoints refuse
# to run before the reviewed root-owned broker has been installed.
pub4_rcctl() {
  local action=${1:-} service=${2:-}
  case "$action" in
    check|get|start|stop|restart) ;;
    *) log_err "pub4_rcctl: refused action: $action"; return 2 ;;
  esac
  case "$service" in
    master|brgen|bsdports|master_jobs|brgen_jobs|bsdports_jobs) ;;
    *) log_err "pub4_rcctl: refused service: $service"; return 2 ;;
  esac
  [[ -x /usr/local/sbin/pub4-admin ]] || {
    log_err "pub4_rcctl: pub4-admin is missing; run reviewed OPENBSD/OPERATOR.sh first"
    return 1
  }
  "${_PRIV}" /usr/local/sbin/pub4-admin service "$action" "$service"
}

# deploy_status APP_NAME STEP [STATE] — single source of truth for "is a
# deploy running right now and what step is it on." Before this, the only way
# to tell a live deploy apart from a hung/crashed process was ps/rcctl
# archaeology (grepping for db:schema:load, bin/ci, etc. and guessing from
# elapsed CPU time). STATE defaults to "running"; pass "done" or "failed" to
# close out the run. One file per app (not one shared file) so concurrent
# deploys of different apps don't clobber each other's state.
# Read with: cat /var/db/pub4/deploy_status/<app>.json (or `bin/vps-state`).
DEPLOY_STATUS_DIR=/var/db/pub4/deploy_status
deploy_status() {
  local app=$1 step=$2 state=${3:-running}
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  DEPLOY_STATUS_STARTED_AT=${DEPLOY_STATUS_STARTED_AT:-$now}

  [[ -x /usr/local/sbin/pub4-admin ]] || {
    log_warn "deploy_status: pub4-admin missing; status not written"
    return 0
  }
  ${_PRIV} /usr/local/sbin/pub4-admin deploy-status "$app" "$step" "$state" || {
    log_warn "deploy_status: broker write failed for ${app}/${step}"
    return 0
  }
}
