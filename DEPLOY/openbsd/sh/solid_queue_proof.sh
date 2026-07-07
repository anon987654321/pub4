#!/usr/bin/env sh
# Verify Solid Queue supervisor is alive for a Rails app on vm23.
set -eu

app=${1:-}
[ -n "$app" ] || { echo "usage: solid_queue_proof.sh APP" >&2; exit 2; }

app_dir=/home/${app}/app
[ -d "$app_dir" ] || { echo "missing $app_dir" >&2; exit 1; }

doas su -m "$app" -c "export HOME=/home/${app}; cd ${app_dir} && bundle34 exec rails runner -e production \"n = SolidQueue::Process.count; puts \\\"solid_queue: ${app} processes=\\\${n}\\\"; exit(n.positive? ? 0 : 1)\""