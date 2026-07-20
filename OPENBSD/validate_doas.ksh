#!/bin/ksh
# Install /etc/doas.conf from repo with trailing-newline fix and dev-user validation.
# Source for functions, or run: ksh validate_doas.ksh check|install SRC [tag]

validate_doas_works() {
  su dev -c 'doas id' 2>/dev/null | grep -q 'uid=0(root)'
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
  typeset tmp=/tmp/doas.conf.install.$$

  [ -r "$src" ] || return 0
  [ -w /etc/doas.conf ] || return 0
  cmp -s /etc/doas.conf "$src" 2>/dev/null && return 0

  mkdir -p "$bakdir" 2>/dev/null || return 1
  backup="$bakdir/doas.conf.$(date +%s).bak"
  [ -f /etc/doas.conf ] && cp /etc/doas.conf "$backup"

  cp "$src" "$tmp" || return 1
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
