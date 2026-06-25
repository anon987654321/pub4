#!/usr/bin/env zsh
# Run one Rails app CI on vm23 with mutex + load gate (serial operator entrypoint).
# Usage: zsh DEPLOY/sh/vps_ci.sh brgen
set -euo pipefail

app=${1:-}
[[ -n $app ]] || { print -u2 "usage: vps_ci.sh APP"; exit 2 }

repo=${PUB4_ROOT:-/home/dev/pub4}
app_dir=/home/${app}/app
[[ -d $app_dir ]] || { print -u2 "missing $app_dir"; exit 1 }

export PUB4_CI_GUARD=1
export PUB4_RAILS_ROOT=${PUB4_RAILS_ROOT:-$repo/DEPLOY/rails}

sync_from_repo() {
  local src=$repo/DEPLOY/rails/$app
  [[ -d $src ]] || return 0
  doas sh -c "
    cp ${src}/db/seeds.rb ${app_dir}/db/seeds.rb 2>/dev/null && chown ${app}:${app} ${app_dir}/db/seeds.rb
    mkdir -p ${app_dir}/shared/lib/pub4 ${app_dir}/shared/config
    cp ${repo}/DEPLOY/rails/shared/config/ci.rb ${app_dir}/shared/config/ci.rb
    cp ${repo}/DEPLOY/rails/shared/lib/pub4/ci_guard.rb ${app_dir}/shared/lib/pub4/ci_guard.rb
    chown -R ${app}:${app} ${app_dir}/shared/lib ${app_dir}/shared/config/ci.rb
  "
}

npm_cache=/home/${app}/.npm
cache_home=/home/${app}/.cache
print "vps_ci: $app (sync + mutex + load gate)"
sync_from_repo
doas sh -c "su -m ${app} -c 'export HOME=/home/${app}; export PUB4_CI_GUARD=1; export NPM_CONFIG_CACHE=${npm_cache}; export XDG_CACHE_HOME=${cache_home}; export BUNDLE_USER_HOME=/home/${app}/.bundle; cd ${app_dir} && bundle34 exec bin/ci'"