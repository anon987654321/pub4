#!/usr/bin/env zsh
set -euo pipefail
# _bundle.sh — bundler and npm-cache helpers.
# Source this file; do not execute directly. Requires _core.sh sourced first.

bundle_exec() {
  local bundle_bin
  bundle_bin=$(command -v bundle34 2>/dev/null || command -v bundle)
  "$bundle_bin" "$@"
}

add_gem() {
  local gem=$1 ver=${2:-}
  if ! grep -q "\"${gem}\"" Gemfile 2>/dev/null; then
    if [[ -n $ver ]]; then
      print "gem \"${gem}\", \"${ver}\"" >> Gemfile
    else
      print "gem \"${gem}\"" >> Gemfile
    fi
    log_ok "gem ${gem} added"
  else
    log_ok "gem ${gem} already present"
  fi
}

add_gem_group() {
  local groups=$1; shift
  local -a gems=("$@")
  if ! grep -q "gem \"${gems[1]}\"" Gemfile 2>/dev/null; then
    {
      print "group :${groups//,/, :} do"
      for g in "${gems[@]}"; do print "  gem \"$g\""; done
      print "end"
    } >> Gemfile
  fi
}

# ensure_npm_cache APP_NAME — sass-embedded native build must not write /root/.npm via doas.
ensure_npm_cache() {
  local app_name=$1
  local npm_cache="/home/${app_name}/.npm"
  ${_PRIV} mkdir -p "$npm_cache"
  ${_PRIV} chown "${app_name}:${app_name}" "$npm_cache"
}

# bundle_install_as_app APP_NAME APP_DIR — production bundle as app user with app-owned npm cache.
bundle_install_as_app() {
  local app_name=$1
  local app_dir=$2
  ensure_npm_cache "$app_name"
  local npm_cache="/home/${app_name}/.npm"
  ${_PRIV} sh -c "su -m ${app_name} -c 'export HOME=/home/${app_name}; export NPM_CONFIG_CACHE=${npm_cache}; cd ${app_dir} && bundle config set --local frozen false && bundle config set --local deployment true && bundle config set --local without \"development test\" && RAILS_ENV=production bundle install'"
}

# bundle_cas_* — immutable SHA-256 store for gem artifacts shared by pub4 applications.
# Bundler remains authoritative for installed gems; CAS only deduplicates immutable .gem bytes.
bundle_cas_root() {
  print -- "${SHARED_BUNDLE_CACHE:-/var/cache/pub4/bundle/ruby34}/cas/sha256"
}

bundle_cas_digest() {
  ruby34 -rdigest -e 'print Digest::SHA256.file(ARGV.fetch(0)).hexdigest' "$1"
}

bundle_cas_store() {
  local source=$1
  local digest
  local root
  local target

  [[ -f $source ]] || return 0
  root=$(bundle_cas_root)
  digest=$(bundle_cas_digest "$source")
  target="${root}/${digest[1,2]}/${digest[3,2]}/${digest}.gem"
  ${_PRIV} mkdir -p "${target:h}"
  [[ -f $target ]] || ${_PRIV} cp "$source" "$target"
}

bundle_cas_capture_dir() {
  local source_dir=$1
  local gem

  [[ -d $source_dir ]] || return 0
  while IFS= read -r gem; do
    bundle_cas_store "$gem"
  done < <(find "$source_dir" -type f -name "*.gem" -print)
}

bundle_cas_hydrate() {
  local app_name=$1
  local app_dir=$2
  local root
  local target
  local source

  root=$(bundle_cas_root)
  [[ -d $root ]] || return 0
  target="${app_dir}/.bundle/cache"
  ${_PRIV} mkdir -p "$target"
  while IFS= read -r source; do
    local gem="${source:t}"
    [[ -f "${target}/${gem}" ]] && continue
    ${_PRIV} ln "$source" "${target}/${gem}" 2>/dev/null || ${_PRIV} cp "$source" "${target}/${gem}"
  done < <(find "$root" -type f -name "*.gem" -print)
  ${_PRIV} chown -R "${app_name}:${app_name}" "$target"
}

bundle_cas_prepare() {
  local app_name=$1
  local app_dir=$2
  local shared="${SHARED_BUNDLE_CACHE:-/var/cache/pub4/bundle/ruby34}"

  ${_PRIV} mkdir -p "${shared}/cas/sha256"
  bundle_cas_capture_dir "${shared}/cache"
  bundle_cas_hydrate "$app_name" "$app_dir"
}

bundle_cas_capture() {
  local app_name=$1
  local app_dir=$2
  local cache_dir="${app_dir}/.bundle/cache"

  bundle_cas_capture_dir "$cache_dir"
  ${_PRIV} chown -R "${app_name}:${app_name}" "$cache_dir" 2>/dev/null || true
}

# bundle_install_as_app APP_NAME APP_DIR — production bundle as app user with app-owned npm cache.
bundle_install_as_app() {
  local app_name=$1
  local app_dir=$2
  bundle_cas_prepare "$app_name" "$app_dir"
  ensure_npm_cache "$app_name"
  local npm_cache="/home/${app_name}/.npm"
  ${_PRIV} sh -c "su -m ${app_name} -c 'export HOME=/home/${app_name}; export NPM_CONFIG_CACHE=${npm_cache}; cd ${app_dir} && bundle config set --local frozen false && bundle config set --local deployment true && bundle config set --local without \"development test\" && RAILS_ENV=production bundle install'"
  bundle_cas_capture "$app_name" "$app_dir"
}
