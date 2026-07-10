#!/usr/bin/env zsh
# @sync.sh — copy-tree sync and shared-file overlays for copy-tree deploy.
# Source this file; do not execute directly. Requires @core.sh sourced first.

sync_tree() {
  local src=$1 dst=$2
  local delete=${3:-1}
  ${_PRIV} mkdir -p "$dst"
  if [[ -n ${SYNC_USE_OPENRSYNC:-} ]]; then
    if [[ $delete == 1 ]]; then
      ${_PRIV} openrsync -a --delete "${src%/}/." "${dst%/}/" && return 0
    else
      ${_PRIV} openrsync -a "${src%/}/." "${dst%/}/" && return 0
    fi
    log_warn "openrsync failed; falling back to tar copy"
  fi
  if [[ $delete == 1 ]]; then
    ${_PRIV} sh -c 'cd "$1" && for entry in * .[!.]* ..?*; do
      [[ -e "$entry" ]] || continue
      case "$entry" in db|storage|log|tmp|vendor|.bundle) continue ;; esac
      rm -rf -- "$entry"
    done' _ "${dst%/}" 2>/dev/null || true
  fi
  ${_PRIV} sh -c "cd '${src%/}' && tar cf - ." | ${_PRIV} sh -c "cd '${dst%/}' && tar xf -"
  ${_PRIV} find "${dst%/}" -name '._*' -delete 2>/dev/null || true
}

already_done() {
  local sentinel=$1
  [[ -f $sentinel ]] && { log_warn "Already set up ($sentinel exists). Skipping."; return 0; }
  return 1
}

# overlay_shared_initializers APP_DIR — shared config wins over stale per-app copies
overlay_shared_initializers() {
  local app_dir=$1
  local shared_init=${PUB4_RAILS_ROOT:-/home/dev/pub4/RAILS}/shared/config/initializers
  [[ -d $shared_init ]] || return 0
  sync_tree "$shared_init" "${app_dir}/config/initializers"
  log_ok "shared initializers overlaid"
}

# overlay_shared_public APP_DIR — merge shared/public (tokens.css, minimal-ui.css, icons)
overlay_shared_public() {
  local app_dir=$1
  local shared_public=${PUB4_RAILS_ROOT:-/home/dev/pub4/RAILS}/shared/public
  [[ -d $shared_public ]] || return 0
  sync_tree "$shared_public" "${app_dir}/public" 0
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

# brgen cannot read /home/dev (mode 700) — copy Radio Bergen manifest into the app tree.
overlay_brgen_radio_manifest() {
  local app_dir=$1
  local repo=${PUB4_ROOT:-/home/dev/pub4}
  local manifest=${repo}/MASTER/tools/audio/radio_bergen_tracks.yml
  local lessons=${repo}/MASTER/data/lessons/pub_archive_restore.yml

  [[ -f $manifest ]] || { log_err "missing Radio Bergen manifest: $manifest"; exit 1; }

  doas mkdir -p "${app_dir}/config/radio_bergen"
  doas cp "$manifest" "${app_dir}/config/radio_bergen/tracks.yml"
  [[ -f $lessons ]] && doas cp "$lessons" "${app_dir}/config/radio_bergen/archive_lessons.yml"
  doas chown -R brgen:brgen "${app_dir}/config/radio_bergen"
  log "ok Radio Bergen manifest overlaid → config/radio_bergen/"
}
