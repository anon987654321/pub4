#!/usr/bin/env zsh
# Production push: master + brgen + amber (serial). Seeds Bergen demo after brgen.
# Usage (on vm23): zsh DEPLOY/openbsd/sh/vps_production_push.sh
set -euo pipefail

repo=${PUB4_ROOT:-/home/dev/pub4}
cd "$repo"
git pull --ff-only origin main

echo "==> master"
zsh "$repo/DEPLOY/openbsd/sh/vps_deploy_master.sh"

echo "==> brgen"
zsh "$repo/DEPLOY/bin/vps-deploy" brgen

echo "==> bergen demo seed"
doas -u brgen sh -c 'cd /home/brgen/app && RAILS_ENV=production bundle exec rails runner "city = City.find_by(domain: \"brgen.no\"); raise \"no city\" unless city; Brgen::BergenDemoSeeder.new(city).seed!; puts \"posts=#{Post.where(city: city).count}\""'

echo "==> amber"
zsh "$repo/DEPLOY/bin/vps-deploy" amber

echo "==> health"
for svc in master brgen amber; do
  doas rcctl check "$svc"
done
curl -fsS http://127.0.0.1:53187/up >/dev/null && echo "master /up ok"
curl -fsS http://127.0.0.1:38182/up >/dev/null && echo "brgen /up ok"
curl -fsS http://127.0.0.1:61352/up >/dev/null && echo "amber /up ok"

echo "==> production push complete"