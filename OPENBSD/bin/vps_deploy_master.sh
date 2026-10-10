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
# SSH and direct invocation use a non-login shell; pin the OpenBSD package path.
export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
ROOT="${ROOT:-/home/dev/pub4}"
. "$ROOT/OPENBSD/lib/ruby_select.sh"
WEB="$ROOT/RAILS/master_web"

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

# Primary database. RAILS/master_web's migrations reach ai.brgen.no's
# production.sqlite3 through this step and no other, so a deploy without it
# ships code against a schema that is behind.
#
# db:prepare is idempotent: it creates the database when absent, loads the
# schema when empty, and otherwise applies only pending migrations.
# Gems first: db:prepare is the first `bundle exec`, and a gem the pull just
# added (ferrum-0.17.2, 2026-09-24) stopped the deploy there with GemNotFound
# while the install that would have fixed it waited two steps later.
echo "==> bundle"
# dev cannot write the system gem directory, and Bundler falls back to it
# (mkdir /usr/local/lib/ruby/gems/3.4/cache/bundler) unless a path is set. The
# path lives in each Gemfile's .bundle/config so rc.d's `bundle exec` as master
# finds the same gems; /home/dev is group _pub4ci, which master belongs to.
BUNDLE_PATH_DEV=/home/dev/.bundle/master
# `bundle config set --local` makes Bundler 4 re-resolve and rewrite Gemfile.lock,
# and on the box that rewrite dropped the Rails git source, so the next
# `bundle exec` died with "git source ... is not yet checked out". Write a setting
# only when it is absent; the environment carries it for this script's own calls.
bundle_config_once() { # dir key value
  grep -qs "^BUNDLE_$2:" "$1/.bundle/config" || (cd "$1" && "$BUNDLE" config set --local "$2" "$3")
}
bundle_config_once "$WEB" WITHOUT 'development:test'
bundle_config_once "$WEB" PATH "$BUNDLE_PATH_DEV"
export BUNDLE_WITHOUT=development:test BUNDLE_PATH="$BUNDLE_PATH_DEV"
"$BUNDLE" check 2>/dev/null || "$BUNDLE" install
# The tts-worker and media tools boot from MASTER/Gemfile, not web's. rc.d/master
# only checks it now, because it runs as root; installing belongs here, as dev.
bundle_config_once "$ROOT/MASTER" PATH "$BUNDLE_PATH_DEV"
(cd "$ROOT/MASTER" && { BUNDLE_GEMFILE=Gemfile "$BUNDLE" check >/dev/null 2>&1 || BUNDLE_GEMFILE=Gemfile "$BUNDLE" install; })

echo "==> db prepare"
BUNDLE_WITHOUT=development:test "$BUNDLE" exec rails db:prepare

echo "==> assets precompile"
# rc.d master precompiles as root; dev cannot rewrite root-owned public/assets/assets.
doas rm -rf public/assets
doas chown -R dev:dev public
BUNDLE_WITHOUT=development:test "$BUNDLE" exec rails assets:build_face_runtime assets:build_face_modules_bundle assets:build_face_vision_bundle 2>/dev/null || true
BUNDLE_WITHOUT=development:test "$BUNDLE" exec rails assets:precompile
# The asset gate, through whichever door exists. MASTER/gates/runner.rb was
# deleted on 2026-09-16 and every deploy script still named it, so `vps-deploy
# master` died here under set -e with the box half deployed: new assets on disk,
# the old process still serving them. The gate itself lives in MASTER/gates and
# runs either way.
if [ -f "$ROOT/MASTER/gates/runner.rb" ]; then
  BUNDLE_WITHOUT=development:test "$BUNDLE" exec ruby "$ROOT/MASTER/gates/runner.rb" master_web_assets
else
  BUNDLE_WITHOUT=development:test "$BUNDLE" exec ruby -e '
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
