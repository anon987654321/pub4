#!/bin/ksh
# Verify Solid Queue supervisor is alive for a Rails app on vm23.
set -eu

app=${1:-}
[[ -n $app ]] || { print -u2 "usage: solid_queue_proof.sh APP"; exit 2; }

app_dir=/home/${app}/app
[[ -d $app_dir ]] || { print -u2 "missing $app_dir"; exit 2; }

doas ksh -c "
  [ -r /etc/${app}.env ] && . /etc/${app}.env
  [ -f /etc/rails/${app}.env ] && . /etc/rails/${app}.env
  : \"\${SECRET_KEY_BASE:?missing SECRET_KEY_BASE in /etc/${app}.env}\"
  su -m ${app} -c \"
    export HOME=/home/${app}
    export RAILS_ENV=production
    export SECRET_KEY_BASE=\${SECRET_KEY_BASE}
    cd ${app_dir} && bundle34 exec rails runner -e production \\\"n = SolidQueue::Process.count; puts \\\\\\\"solid_queue: ${app} processes=\\\\\\\${n}\\\\\\\"; exit(n.positive? ? 0 : 1)\\\"
  \"
"