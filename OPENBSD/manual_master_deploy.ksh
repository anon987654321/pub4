#!/bin/ksh
# Manual MASTER deploy — use when vps_deploy_master.sh stalls.
# Run on VPS: tmux new-session -d -s masterdeploy /home/dev/pub4/OPENBSD/manual_master_deploy.ksh
# Watch: tail -f /tmp/master_manual.log


# set -e and pipefail: a failed step inside a manual deploy used to continue
# to the next one, and with only set -e a failed `sysctl | awk` yields an empty
# string that the caller then compares against nothing.
set -e
set -o pipefail
LOG=/tmp/master_manual.log
exec >"$LOG" 2>&1
set -x
_fail=0
echo "START $(date -u)"

pkill -9 -f vps_deploy_master 2>/dev/null
pkill -9 -f "rails assets:precompile" 2>/dev/null
pkill -9 -f "bundle34 exec rails assets" 2>/dev/null
pkill -9 -f "rcctl restart master" 2>/dev/null
pkill -9 -f "falcon.*53187" 2>/dev/null
sleep 1

doas rcctl stop master 2>/dev/null
echo "SHA=$(git -C /home/dev/pub4 rev-parse --short HEAD)"

cd /home/dev/pub4/MASTER/web || exit 1
export RAILS_ENV=production
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(openssl rand -hex 16)}"

MANIFEST=/home/dev/pub4/MASTER/web/public/assets/.manifest.json
if [ -f "$MANIFEST" ] && [ "${FORCE_PRECOMPILE:-0}" != "1" ]; then
  echo precompile_skip manifest_exists
else
  echo precompile_start
  bundle34 exec rails assets:build_face_runtime assets:build_face_modules_bundle assets:build_face_vision_bundle || _fail=1
  bundle34 exec rails assets:precompile || _fail=1
fi
ruby34 /home/dev/pub4/RAILS/gates/runner.rb master_web_assets || _fail=1
if [ "$_fail" -ne 0 ]; then
  echo FAILED precompile_or_gate
  exit 1
fi

echo restart_master
# rc_pre skips face/precompile when artifacts exist (patched /etc/rc.d/master).
doas rcctl restart master &
_rc_pid=$!
_i=0
while kill -0 "$_rc_pid" 2>/dev/null && [ "$_i" -lt 120 ]; do
  curl -fsS "http://127.0.0.1:53187/up" >/dev/null 2>&1 && break
  _i=$((_i + 1))
  sleep 2
done
wait "$_rc_pid" 2>/dev/null || true

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
