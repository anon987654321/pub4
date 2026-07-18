#!/bin/sh
# Deploy MASTER web + lib to vm23 after git pull.
# Usage (from dev laptop):
#   zsh OPENBSD/lib/ssh_vm23.sh exec 'zsh /home/dev/pub4/OPENBSD/vps_deploy_master.sh'
#   zsh OPENBSD/vps_deploy_master.sh --from-laptop

if [ "${1:-}" = "--from-laptop" ]; then
  shift
  _lib="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib/ssh_vm23.sh"
  exec zsh "$_lib" exec "zsh /home/dev/pub4/OPENBSD/vps_deploy_master.sh" "$@"
fi

set -e
ROOT="${ROOT:-/home/dev/pub4}"
WEB="$ROOT/MASTER/web"

echo "==> git pull"
cd "$ROOT" && git pull origin main

echo "==> assets precompile"
cd "$WEB"
export LANG=C.UTF-8 LC_ALL=C.UTF-8
export RAILS_ENV=production
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(openssl rand -hex 32)}"
# rc.d master precompiles as root; dev cannot rewrite root-owned public/assets/assets.
doas rm -rf public/assets
doas chown -R dev:dev public
bundle34 config set --local without 'development:test' 2>/dev/null || true
BUNDLE_WITHOUT=development:test bundle34 check 2>/dev/null || BUNDLE_WITHOUT=development:test bundle34 install
BUNDLE_WITHOUT=development:test bundle34 exec rails assets:build_face_runtime assets:build_face_modules_bundle assets:build_face_vision_bundle 2>/dev/null || true
BUNDLE_WITHOUT=development:test bundle34 exec rails assets:precompile
BUNDLE_WITHOUT=development:test bundle34 exec ruby "$ROOT/RAILS/master_web_assets_gate.rb"

echo "==> sync rc.d master"
if [ -f "$ROOT/OPENBSD/etc/rc.d/master" ]; then
  doas cp "$ROOT/OPENBSD/etc/rc.d/master" /etc/rc.d/master
fi

echo "==> restart master"
doas rcctl restart master
sleep 4
rcctl check master

echo "==> smoke"
curl -fsS http://127.0.0.1:53187/up
curl -fsS http://127.0.0.1:53187/health | ruby -rjson -e 'h=JSON.parse(STDIN.read); d=h["deploy"]||{}; abort("tts_socket false") if d["tts_socket"]==false; abort("checks.tts false") if h.dig("checks","tts")==false; puts "health ok sha=#{d["git_sha"]} tts_socket=#{d["tts_socket"]}"'
ruby "$WEB/script/probe_http"

echo "==> master deploy ok"
