#!/bin/ksh
# Manual MASTER deploy — use when vps_deploy_master.sh stalls.
# Run on VPS: tmux new-session -d -s masterdeploy /home/dev/pub4/DEPLOY/openbsd/sh/manual_master_deploy.ksh
# Watch: tail -f /tmp/master_manual.log

LOG=/tmp/master_manual.log
exec >"$LOG" 2>&1
set -x
echo "START $(date -u)"

pkill -f vps_deploy_master 2>/dev/null
pkill -f "rails assets:precompile" 2>/dev/null
pkill -f "rcctl restart master" 2>/dev/null
pkill -f "falcon.*53187" 2>/dev/null
sleep 1

doas rcctl stop master 2>/dev/null
echo "SHA=$(git -C /home/dev/pub4 rev-parse --short HEAD)"

cd /home/dev/pub4/MASTER/web || exit 1
export RAILS_ENV=production
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(openssl rand -hex 16)}"

echo precompile_start
bundle34 exec rails assets:build_face_runtime assets:build_face_modules_bundle assets:build_face_vision_bundle
bundle34 exec rails assets:precompile
ruby34 /home/dev/pub4/DEPLOY/rails/master_web_assets_gate.rb

echo restart_master
doas rcctl restart master

i=0
while [ "$i" -lt 60 ]; do
  curl -fsS "http://127.0.0.1:53187/up" >/dev/null 2>&1 && break
  i=$((i + 1))
  sleep 1
done
curl -sS "http://127.0.0.1:53187/up"
echo

doas rcctl restart relayd
curl -sS -m 5 -o /dev/null -w "relayd_https=%{http_code}\n" -H "Host: ai.brgen.no" "https://127.0.0.1/up" -k
ruby34 /home/dev/pub4/MASTER/web/script/probe_http
echo "DONE $(date -u)"