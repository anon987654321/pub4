#!/usr/bin/env zsh
# Run one Rails app CI on vm23 with mutex + load gate (serial operator entrypoint).
# Usage: zsh OPENBSD/sh/vps_ci.sh brgen
set -euo pipefail

app=${1:-}
[[ -n $app ]] || { print -u2 "usage: vps_ci.sh APP"; exit 2 }

repo=${PUB4_ROOT:-/home/dev/pub4}
app_dir=/home/${app}/app
shared_dir=/home/${app}/shared
[[ -d $app_dir ]] || { print -u2 "missing $app_dir"; exit 1 }

export PUB4_CI_GUARD=1
export PUB4_RAILS_ROOT=${PUB4_RAILS_ROOT:-$repo/RAILS}

ensure_ci_lock() {
  doas sh -c "
    rm -f /var/tmp/pub4-ci.lock.holder 2>/dev/null || true
    touch /var/tmp/pub4-ci.lock 2>/dev/null || true
    chmod 666 /var/tmp/pub4-ci.lock 2>/dev/null || true
  "
}

sync_ci_rails_root() {
  local mirror=/home/${app}/pub4-rails
  doas mkdir -p "$mirror"
  doas tar cf - -C "$repo" RAILS | doas sh -c "cd ${mirror} && tar xf -"
  doas chown -R "${app}:${app}" "$mirror"
}

sync_from_repo() {
  local src=$repo/RAILS/$app
  local shared_src=$repo/RAILS/shared
  sync_ci_rails_root
  if [[ -d $src ]]; then
    local -a paths=(test app lib config bin db Gemfile Gemfile.lock)
    local -a existing=()
    local rel
    for rel in "${paths[@]}"; do
      [[ -e $src/$rel ]] && existing+=($rel)
    done
    for rel in ${src}/*.sh(N:t); do existing+=($rel); done
    [[ ${#existing[@]} -eq 0 ]] && return 0
    doas tar cf - -C "$src" "${existing[@]}" | doas sh -c "cd ${app_dir} && tar xf -"
    doas chown -R "${app}:${app}" "${app_dir}/test" "${app_dir}/app" "${app_dir}/lib" \
      "${app_dir}/config" "${app_dir}/bin" "${app_dir}/db" "${app_dir}/Gemfile" "${app_dir}/Gemfile.lock" \
      "${app_dir}"/*.sh(N) 2>/dev/null || true
  fi
  doas mkdir -p "$shared_dir"
  doas tar cf - -C "$shared_src" . | doas sh -c "cd ${shared_dir} && tar xf -"
  doas chown -R "${app}:${app}" "$shared_dir"
}

npm_cache=/home/${app}/.npm
cache_home=/home/${app}/.cache
print "vps_ci: $app (sync + mutex + load gate)"
sync_from_repo
ensure_ci_lock
ci_rails_root=/home/${app}/pub4-rails/RAILS
doas sh -c "su -m ${app} -c 'export HOME=/home/${app}; export PUB4_CI_GUARD=1; export PUB4_CI_APP=${app}; export PUB4_RAILS_ROOT=${ci_rails_root}; export NPM_CONFIG_CACHE=${npm_cache}; export XDG_CACHE_HOME=${cache_home}; export BUNDLE_USER_HOME=/home/${app}/.bundle; cd ${app_dir} && bundle34 config unset without 2>/dev/null || true && bundle34 config unset deployment 2>/dev/null || true && bundle34 install --jobs=2 && bundle34 exec bin/ci'"

sha=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo unknown)
started=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
doas mkdir -p /var/db/pub4 2>/dev/null || true
doas tee "/var/db/pub4/last_deploy_${app}.json" >/dev/null <<EOF
{"app":"${app}","sha":"${sha}","at":"${started}","status":"ci_ok","host":"$(hostname)"}
EOF
