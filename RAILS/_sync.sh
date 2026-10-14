#!/usr/bin/env zsh
set -euo pipefail
# _sync.sh — copy-tree sync and fixed app-user shared-file overlays.
# Source this file; do not execute directly. Requires _core.sh sourced first.

# The tar copy is the default path. openrsync runs only when SYNC_USE_OPENRSYNC
# is set, and a failure there warns and falls through to the same tar copy.
sync_tree() {
  local src=$1 dst=$2
  local delete=${3:-1}

  if [[ -n ${SYNC_USE_OPENRSYNC:-} && $delete != 1 ]]; then
    ${_PRIV} openrsync -a "${src%/}/." "${dst%/}/" && return 0
    log_warn "openrsync failed; falling back to tar overlay"
  elif [[ -n ${SYNC_USE_OPENRSYNC:-} ]]; then
    log_warn "openrsync disabled for destructive sync; using staged tar copy"
  fi

  if [[ $delete == 1 ]]; then
    local parent=${dst:h}
    local base=${dst:t}
    local stage="${parent}/.${base}.sync.$$"
    local old="${parent}/.${base}.previous.$$"

    ${_PRIV} rm -rf "$stage" "$old"
    ${_PRIV} mkdir -p "$stage"

    if ! tar cf - -C "${src%/}" . | ${_PRIV} tar xf - -C "${stage%/}"; then
      ${_PRIV} rm -rf "$stage"
      log_err "staged tar copy failed; destination left untouched"
      return 1
    fi

    if [[ -e "$dst" ]]; then
      if ! ${_PRIV} mv "$dst" "$old"; then
        ${_PRIV} rm -rf "$stage"
        log_err "could not stage current destination"
        return 1
      fi
    else
      old=""
    fi
    if ! ${_PRIV} mv "$stage" "$dst"; then
      if [[ -n "$old" ]]; then
        ${_PRIV} mv "$old" "$dst" || log_err "CRITICAL: destination restore failed"
      fi
      ${_PRIV} rm -rf "$stage"
      log_err "could not activate staged destination"
      return 1
    fi
    [[ -n "$old" ]] && ${_PRIV} rm -rf "$old"
  else
    ${_PRIV} mkdir -p "$dst"
    if ! tar cf - -C "${src%/}" . | ${_PRIV} tar xf - -C "${dst%/}"; then
      log_err "tar overlay failed"
      return 1
    fi
  fi

  local entry
  for entry in "${dst%/}"/**/._*(N) "${dst%/}"/._*(N); do
    [[ -e $entry ]] || continue
    ${_PRIV} rm -f "$entry"
  done
}
# rails_sync_app_tree APP_NAME MODE — fixed app-user tree synchronization.
# Source and destination paths are owned by the installed broker helper, not caller input.
rails_sync_app_tree() {
  local app_name=$1 mode=$2
  case "$app_name" in
    brgen|amber|bsdports) ;;
    *) log_err "rails_sync_app_tree: refused app: $app_name"; return 2 ;;
  esac
  case "$mode" in
    app|shared) ;;
    verticals)
      [[ $app_name == brgen ]] || { log_err "rails_sync_app_tree: verticals are brgen-only"; return 2; }
      ;;
    *) log_err "rails_sync_app_tree: refused mode: $mode"; return 2 ;;
  esac
  [[ -x /usr/local/sbin/pub4-admin ]] || {
    log_err "rails_sync_app_tree: pub4-admin is missing; run OPERATOR.sh before deploying"
    return 1
  }
  "${_PRIV}" /usr/local/sbin/pub4-admin rails-sync "$app_name" "$mode"
}
# overlay_shared_initializers APP_DIR — shared config wins over stale per-app copies
overlay_shared_initializers() {
  local app_dir=$1
  local shared_init=${PUB4_RAILS_ROOT:-/home/dev/pub4/RAILS}/__shared/config/initializers
  [[ -d $shared_init ]] || return 0
  local app_name=${app_dir:h:t}
  [[ -x /usr/local/sbin/pub4-admin ]] || {
    log_err "shared initializer overlay refused: pub4-admin is missing"
    return 1
  }
  run_rails_as_app "$app_name" "$app_dir" "overlay-initializers" || return $?
  log_ok "shared initializers overlaid (merge, app-specific files preserved)"
}

# overlay_shared_public APP_DIR — merge shared/public (tokens, error pages, fonts).
# Never clobber per-app brand icons/manifests (amber palette, etc.).
overlay_shared_public() {
  local app_dir=$1
  local shared_public=${PUB4_RAILS_ROOT:-/home/dev/pub4/RAILS}/__shared/public
  [[ -d $shared_public ]] || return 0
  local app_name=${app_dir:h:t}
  [[ -x /usr/local/sbin/pub4-admin ]] || {
    log_err "shared public overlay refused: pub4-admin is missing"
    return 1
  }
  run_rails_as_app "$app_name" "$app_dir" "overlay-public" || return $?
  log_ok "shared public assets and bin stubs overlaid"
}
