#!/usr/bin/env zsh
set -euo pipefail
# _bundle.sh — bundler and npm-cache helpers.
# Source this file; do not execute directly. Requires _core.sh sourced first.

bundle_exec() {
  "$BUNDLE" "$@"
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
  run_rails_as_app "$app_name" "/home/${app_name}/app" "npm-cache"
}

# bundle_cas_* — immutable SHA-256 store for gem artifacts shared by pub4 applications.
# The broker owns only the fixed /var/cache/pub4/bundle/<ruby-key> namespace; the
# selected app owns extraction into its own cache. No arbitrary paths cross doas.
bundle_cas_root() {
  print -- "/var/cache/pub4/bundle/${RUBY_CACHE_KEY}/cas/sha256"
}

bundle_cas_prepare() {
  local app_name=$1 app_dir=$2
  [[ $app_name == brgen || $app_name == amber || $app_name == bsdports ]] || {
    log_err "bundle_cas_prepare: refused app: $app_name"
    return 2
  }
  [[ $app_dir == "/home/${app_name}/app" ]] || {
    log_err "bundle_cas_prepare: refused app path: $app_dir"
    return 2
  }
  [[ -x /usr/local/sbin/pub4-admin ]] || {
    log_err "bundle_cas_prepare: pub4-admin is missing; run OPERATOR.sh before deploying"
    return 1
  }
  "${_PRIV}" /usr/local/sbin/pub4-admin bundle-cache "$app_name" prepare "$RUBY_CACHE_KEY" || return $?
  "${_PRIV}" /usr/local/sbin/pub4-admin bundle-cache "$app_name" import "$RUBY_CACHE_KEY" || return $?
  run_rails_as_app "$app_name" "$app_dir" "bundle-cas-hydrate" "$RUBY_CACHE_KEY"
}

bundle_cas_capture() {
  local app_name=$1 app_dir=$2
  [[ $app_name == brgen || $app_name == amber || $app_name == bsdports ]] || {
    log_err "bundle_cas_capture: refused app: $app_name"
    return 2
  }
  [[ $app_dir == "/home/${app_name}/app" ]] || {
    log_err "bundle_cas_capture: refused app path: $app_dir"
    return 2
  }
  "${_PRIV}" /usr/local/sbin/pub4-admin bundle-cache "$app_name" capture "$RUBY_CACHE_KEY"
}

# bundle_install_as_app APP_NAME APP_DIR — production bundle as the app user.
bundle_install_as_app() {
  local app_name=$1
  local app_dir=$2
  bundle_cas_prepare "$app_name" "$app_dir"
  run_rails_as_app "$app_name" "$app_dir" "bundle-install"
  bundle_cas_capture "$app_name" "$app_dir"
}
