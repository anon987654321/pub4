#!/bin/ksh
# Install /etc/doas.conf from repo with trailing-newline fix and dev-user validation.
# Source for functions, or run: ksh validate_doas.ksh check|install SRC [tag]

# A canary from doas.conf's setenv allowlist. The dev rule dropped `keepenv` for a
# `setenv { … }` list, and the old check could not see the difference: `doas id` keeps
# working perfectly with an empty or wrong allowlist, so the rollback net covered the
# lockout case and not the case the change actually risks. A lost variable would then
# surface as OPERATOR.sh refusing --stage-1 with a confusing "rerun with
# I_UNDERSTAND_DNS_WIPE=1" — half an hour after the config that broke it landed.

# set -e and pipefail: a failed step inside a manual deploy used to continue
# to the next one, and with only set -e a failed `sysctl | awk` yields an empty
# string that the caller then compares against nothing.
set -e
set -o pipefail
DOAS_ENV_CANARY=${DOAS_ENV_CANARY:-I_UNDERSTAND_DNS_WIPE}

validate_doas_can_reach_root() {
  su dev -c 'doas id' 2>/dev/null | grep -q 'uid=0(root)'
}

validate_doas_passes_env() {
  su dev -c "${DOAS_ENV_CANARY}=canary doas printenv ${DOAS_ENV_CANARY}" 2>/dev/null |
    grep -q '^canary$'
}

validate_doas_works() {
  validate_doas_can_reach_root || return 1
  validate_doas_passes_env || {
    logger -t doas-guard "doas.conf reaches root but drops ${DOAS_ENV_CANARY} — setenv allowlist is wrong"
    return 1
  }
  return 0
}

ensure_doas_trailing_newline() {
  typeset f=$1
  [ -f "$f" ] || return 1
  if [ "$(tail -c1 "$f" | wc -c)" -eq 0 ]; then
    echo >> "$f"
  fi
  return 0
}

rollback_doas_conf() {
  typeset backup=$1
  [ -n "$backup" ] && [ -f "$backup" ] || return 1
  cp "$backup" /etc/doas.conf
  logger -t doas-guard "rolled back /etc/doas.conf from $backup"
  return 0
}

install_doas_conf_from_repo() {
  typeset src=$1
  typeset tag=${2:-doas-guard}
  typeset backup=""
  typeset bakdir=/var/backups/openbsd_setup
  typeset tmp=""

  [ -r "$src" ] || return 0
  [ -w /etc/doas.conf ] || return 0
  cmp -s /etc/doas.conf "$src" 2>/dev/null && return 0

  mkdir -p "$bakdir" 2>/dev/null || return 1
  chmod 700 "$bakdir" 2>/dev/null || true
  backup="$bakdir/doas.conf.$(date +%s).bak"
  [ -f /etc/doas.conf ] && cp /etc/doas.conf "$backup"

  # The staging file was /tmp/doas.conf.install.$$ — a PID-predictable name in a
  # world-writable directory, written and copied by root with no -h/-P
  # (OPENBSD/data/debt.yml: root_dot_sources_dev_owned_repo_every_5min). Winning that
  # race let a local account decide what root wrote into /etc/doas.conf, which is
  # root code execution by definition. mktemp in the root-owned 0700 backup
  # directory removes the vector rather than trying to outrun it.
  tmp=$(mktemp "$bakdir/doas.conf.install.XXXXXXXXXX") || return 1

  cp "$src" "$tmp" || { rm -f "$tmp"; return 1; }
  ensure_doas_trailing_newline "$tmp" || { rm -f "$tmp"; return 1; }
  cp "$tmp" /etc/doas.conf || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"

  if validate_doas_works; then
    logger -t "$tag" "synced /etc/doas.conf from repo (validated)"
    return 0
  fi

  logger -t "$tag" "doas validation failed after installing $src"
  rollback_doas_conf "$backup"
  return 1
}

_run_validate_doas_cli() {
  case ${1:-check} in
  check)
    validate_doas_works
    return $?
    ;;
  install)
    [ -n "${2:-}" ] || { echo "usage: validate_doas.ksh install SRC [tag]" >&2; return 2; }
    install_doas_conf_from_repo "$2" "${3:-doas-guard}"
    return $?
    ;;
  *)
    echo "usage: validate_doas.ksh check|install SRC [tag]" >&2
    return 2
    ;;
  esac
}

case $0 in
*/validate_doas.ksh)
  _run_validate_doas_cli "$@"
  exit $?
  ;;
esac
