#!/bin/sh
# Deploy MASTER web + lib to vm23 after git pull.
# Usage (from dev laptop):
#   ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226 'zsh /home/dev/pub4/DEPLOY/sh/vps_deploy_master.sh'

set -e
ROOT="${ROOT:-/home/dev/pub4}"
WEB="$ROOT/MASTER/web"

echo "==> git pull"
cd "$ROOT" && git pull origin main

echo "==> assets precompile"
cd "$WEB"
export RAILS_ENV=production
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(openssl rand -hex 32)}"
# Propshaft wedges when public/assets/ is stale or root-owned from rc.d precompile.
doas rm -rf public/assets 2>/dev/null || rm -rf public/assets 2>/dev/null || true
doas chown -R dev:dev public 2>/dev/null || true
bundle exec rails assets:precompile
bundle exec ruby "$ROOT/DEPLOY/rails/master_web_assets_gate.rb"

echo "==> restart master"
doas rcctl restart master
sleep 4
rcctl check master

echo "==> smoke"
curl -fsS http://127.0.0.1:53187/up
curl -fsS http://127.0.0.1:53187/ | grep -q domain-cluster-bar
ruby "$WEB/script/probe_http" || true

echo "==> master deploy ok"
