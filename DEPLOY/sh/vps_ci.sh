#!/usr/bin/env zsh
# Run one Rails app CI on vm23 with mutex + load gate (serial operator entrypoint).
# Usage: zsh DEPLOY/sh/vps_ci.sh brgen
set -euo pipefail

app=${1:-}
[[ -n $app ]] || { print -u2 "usage: vps_ci.sh APP"; exit 2 }

repo=${PUB4_ROOT:-/home/dev/pub4}
app_dir=/home/${app}/app
shared_dir=/home/${app}/shared
[[ -d $app_dir ]] || { print -u2 "missing $app_dir"; exit 1 }

export PUB4_CI_GUARD=1
export PUB4_RAILS_ROOT=${PUB4_RAILS_ROOT:-$repo/DEPLOY/rails}

ensure_ci_lock() {
  doas sh -c "
    rm -f /var/tmp/pub4-ci.lock.holder 2>/dev/null || true
    touch /var/tmp/pub4-ci.lock 2>/dev/null || true
    chmod 666 /var/tmp/pub4-ci.lock 2>/dev/null || true
  "
}

sync_from_repo() {
  local src=$repo/DEPLOY/rails/$app
  local shared_src=$repo/DEPLOY/rails/shared
  if [[ -d $src ]]; then
    local -a paths=(test app lib config bin db/seeds.rb db/migrate)
    local -a existing=()
    local rel
    for rel in "${paths[@]}"; do
      [[ -e $src/$rel ]] && existing+=($rel)
    done
    for rel in ${src}/*.sh(N:t); do existing+=($rel); done
    [[ ${#existing[@]} -eq 0 ]] && return 0
    doas tar cf - -C "$src" "${existing[@]}" | doas sh -c "cd ${app_dir} && tar xf -"
    doas chown -R "${app}:${app}" "${app_dir}/test" "${app_dir}/app" "${app_dir}/lib" \
      "${app_dir}/config" "${app_dir}/bin" "${app_dir}/db" "${app_dir}"/*.sh(N) 2>/dev/null || true
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
doas sh -c "su -m ${app} -c 'export HOME=/home/${app}; export PUB4_CI_GUARD=1; export PUB4_RAILS_ROOT=${repo}/DEPLOY/rails; export NPM_CONFIG_CACHE=${npm_cache}; export XDG_CACHE_HOME=${cache_home}; export BUNDLE_USER_HOME=/home/${app}/.bundle; cd ${app_dir} && bundle34 exec bin/ci'"