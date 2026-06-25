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

npm_cache=/home/${app}/.npm
cache_home=/home/${app}/.cache
print "vps_ci: $app (mutex + load gate)"
doas sh -c "su -m ${app} -c 'export HOME=/home/${app}; export NPM_CONFIG_CACHE=${npm_cache}; export XDG_CACHE_HOME=${cache_home}; cd ${app_dir} && bundle34 exec bin/ci'"