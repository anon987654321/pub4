#!/usr/bin/env zsh
# Production push: master + brgen + amber + bsdports (serial, fast path skips CI).
# Usage (on vm23): zsh OPENBSD/vps_production_push.sh
# Guest demo density: DEMO_SEED_ON_DEPLOY=1 zsh OPENBSD/vps_production_push.sh
set -euo pipefail

repo=${PUB4_ROOT:-/home/dev/pub4}
cd "$repo"
git pull --ff-only origin main

export SKIP_CI=1

echo "==> master"
zsh "$repo/OPENBSD/vps_deploy_master.sh"

echo "==> brgen"
zsh "$repo/OPENBSD/bin/vps-deploy" brgen

# Default ON for guest demo path (Live + marketplace density). Opt out: DEMO_SEED_ON_DEPLOY=0
if [[ ${DEMO_SEED_ON_DEPLOY:-1} == 1 ]]; then
  echo "==> bergen demo seed (posts, Live notes, listings)"
  doas -u brgen sh -c 'cd /home/brgen/app && RAILS_ENV=production bundle exec rails runner "
    city = City.find_by(domain: \"brgen.no\") or raise \"brgen.no city missing\"
    Brgen::BergenDemoSeeder.new(city, attach_media: false).seed!
    puts \"bergen_posts=#{Post.where(city: city).count} live=#{Post.live.where(city: city).count} listings=#{Marketplace::Listing.count} demo=#{Post.exists?(title: \"Regnværsdag på Bryggen\")}\"
  "'
fi

echo "==> amber"
zsh "$repo/OPENBSD/bin/vps-deploy" amber

echo "==> bsdports"
zsh "$repo/OPENBSD/bin/vps-deploy" bsdports

echo "==> health"
for svc in master brgen amber bsdports; do
  doas rcctl check "$svc" || echo "WARN: rcctl check $svc"
done
curl -fsS http://127.0.0.1:53187/up >/dev/null && echo "master /up ok"
curl -fsS http://127.0.0.1:38182/up >/dev/null && echo "brgen /up ok"
curl -fsS http://127.0.0.1:61352/up >/dev/null && echo "amber /up ok"
curl -fsS http://127.0.0.1:47312/up >/dev/null && echo "bsdports /up ok"
if [[ -x $repo/OPENBSD/bin/smoke-apps.sh ]]; then
  sh "$repo/OPENBSD/bin/smoke-apps.sh" || echo "WARN: smoke-apps partial"
fi
ruby "$repo/MASTER/web/script/probe_http" 2>/dev/null || true

echo "==> production push complete"
