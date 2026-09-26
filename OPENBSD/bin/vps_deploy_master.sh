#!/bin/sh
# Deploy MASTER web + lib to vm23 after git pull.
#
# This is the body of `bin/vps-deploy master`, which also writes the deploy
# stamp; run that. Calling this file directly deploys without a stamp, which
# is only right when vps-deploy itself is what is broken.
#
# Usage (from dev laptop):
#   zsh OPENBSD/lib/ssh_vm23.sh exec 'zsh /home/dev/pub4/OPENBSD/bin/vps_deploy_master.sh'
#   zsh OPENBSD/bin/vps_deploy_master.sh --from-laptop

if [ "${1:-}" = "--from-laptop" ]; then
  shift
  _lib="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/ssh_vm23.sh"
  exec zsh "$_lib" exec "zsh /home/dev/pub4/OPENBSD/bin/vps_deploy_master.sh" "$@"
fi

set -eo pipefail
ROOT="${ROOT:-/home/dev/pub4}"
WEB="$ROOT/MASTER/web"

echo "==> git pull"
cd "$ROOT" && git pull --ff-only origin main

cd "$WEB"
export LANG=C.UTF-8 LC_ALL=C.UTF-8
export RAILS_ENV=production
# The build steps below need a secret to boot Rails and never use it; the
# running server takes its real key from /etc/master.env through rc.d/master.
# SECRET_KEY_BASE_DUMMY says that outright, where a random key could be
# mistaken for, or leak into, the real one.
export SECRET_KEY_BASE_DUMMY=1

# Primary database. MASTER/web's migrations reach ai.brgen.no's
# production.sqlite3 through this step and no other, so a deploy without it
# ships code against a schema that is behind.
#
# db:prepare is idempotent: it creates the database when absent, loads the
# schema when empty, and otherwise applies only pending migrations.
# Gems first: db:prepare is the first `bundle34 exec`, and a gem the pull just
# added (ferrum-0.17.2, 2026-09-24) stopped the deploy there with GemNotFound
# while the install that would have fixed it waited two steps later.
echo "==> bundle"
bundle34 config set --local without 'development:test' 2>/dev/null || true
BUNDLE_WITHOUT=development:test bundle34 check 2>/dev/null || BUNDLE_WITHOUT=development:test bundle34 install
# The tts-worker and media tools boot from MASTER/Gemfile, not web's. rc.d/master
# only checks it now, because it runs as root; installing belongs here, as dev.
(cd "$ROOT/MASTER" && BUNDLE_GEMFILE=Gemfile bundle34 check >/dev/null 2>&1 || BUNDLE_GEMFILE=Gemfile bundle34 install)

echo "==> db prepare"
BUNDLE_WITHOUT=development:test bundle34 exec rails db:prepare

echo "==> assets precompile"
# rc.d master precompiles as root; dev cannot rewrite root-owned public/assets/assets.
doas rm -rf public/assets
doas chown -R dev:dev public
BUNDLE_WITHOUT=development:test bundle34 exec rails assets:build_face_runtime assets:build_face_modules_bundle assets:build_face_vision_bundle 2>/dev/null || true
BUNDLE_WITHOUT=development:test bundle34 exec rails assets:precompile
# The asset gate, through whichever door exists. MASTER/gates/runner.rb was
# deleted on 2026-09-16 and every deploy script still named it, so `vps-deploy
# master` died here under set -e with the box half deployed: new assets on disk,
# the old process still serving them. The gate itself lives in MASTER/gates and
# runs either way.
if [ -f "$ROOT/MASTER/gates/runner.rb" ]; then
  BUNDLE_WITHOUT=development:test bundle34 exec ruby "$ROOT/MASTER/gates/runner.rb" master_web_assets
else
  BUNDLE_WITHOUT=development:test bundle34 exec ruby -e '
    require ARGV[0]
    Deploy::MasterWebAssetsGate.run.report!("master web assets ok")
  ' "$ROOT/MASTER/lib/operator/gates.rb"
fi

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
