#!/usr/bin/env zsh
set -euo pipefail
# _sync.sh — copy-tree sync and shared-file overlays for copy-tree deploy.
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

    if ! ${_PRIV} sh -c "cd '${src%/}' && tar cf - ." | ${_PRIV} sh -c "cd '${stage%/}' && tar xf -"; then
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
    if ! ${_PRIV} sh -c "cd '${src%/}' && tar cf - ." | ${_PRIV} sh -c "cd '${dst%/}' && tar xf -"; then
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
# overlay_shared_initializers APP_DIR — shared config wins over stale per-app copies
overlay_shared_initializers() {
  local app_dir=$1
  local shared_init=${PUB4_RAILS_ROOT:-/home/dev/pub4/RAILS}/shared/config/initializers
  [[ -d $shared_init ]] || return 0
  sync_tree "$shared_init" "${app_dir}/config/initializers" 0
  log_ok "shared initializers overlaid (merge, app-specific files preserved)"
}

# overlay_shared_public APP_DIR — merge shared/public (tokens, error pages, fonts).
# Never clobber per-app brand icons/manifests (amber palette, etc.).
overlay_shared_public() {
  local app_dir=$1
  local shared_public=${PUB4_RAILS_ROOT:-/home/dev/pub4/RAILS}/shared/public
  local entry
  [[ -d $shared_public ]] || return 0
  ${_PRIV} mkdir -p "${app_dir}/public"
  for entry in "$shared_public"/*(N) "$shared_public"/.[!.]*(N); do
    [[ -e $entry ]] || continue
    local base=${entry:t}
    case $base in
      icon.svg|icon.png|icon-192.png|apple-touch-icon.png|favicon.ico|manifest.json|manifest.webmanifest)
        [[ -e ${app_dir}/public/$base ]] && continue
        ;;
    esac
    ${_PRIV} cp -R "$entry" "${app_dir}/public/"
  done
  log_ok "shared public assets overlaid"
  overlay_shared_bin "$app_dir"
}

# overlay_shared_bin APP_DIR — ci.rb expects bin/rubocop, brakeman, bundler-audit stubs
overlay_shared_bin() {
  local app_dir=$1
  local shared_bin=${PUB4_RAILS_ROOT:-/home/dev/pub4/RAILS}/shared/bin
  [[ -d $shared_bin ]] || return 0
  ${_PRIV} mkdir -p "${app_dir}/bin"
  for tool in rubocop brakeman bundler-audit; do
    [[ -f ${shared_bin}/${tool} ]] || continue
    ${_PRIV} cp "${shared_bin}/${tool}" "${app_dir}/bin/${tool}"
    ${_PRIV} chmod 755 "${app_dir}/bin/${tool}"
  done
  [[ -f ${PUB4_RAILS_ROOT:-/home/dev/pub4/RAILS}/shared/.rubocop.yml ]] \
    && ${_PRIV} cp "${PUB4_RAILS_ROOT:-/home/dev/pub4/RAILS}/shared/.rubocop.yml" "${app_dir}/.rubocop.yml"
  log_ok "shared bin stubs overlaid"
}

