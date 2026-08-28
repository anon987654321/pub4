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
