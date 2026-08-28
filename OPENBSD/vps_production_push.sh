#!/usr/bin/env zsh
# Production push: master + brgen + amber + bsdports (serial, fast path skips CI).
# Usage (on vm23): zsh OPENBSD/vps_production_push.sh
# Guest demo density: DEMO_SEED_ON_DEPLOY=1 zsh OPENBSD/vps_production_push.sh
set -euo pipefail

repo=${PUB4_ROOT:-/home/dev/pub4}
cd "$repo"
git pull --ff-only origin main

export SKIP_CI=1
# Production push is a fast path: skip full bin/ci runtime gate (OOM-prone on 1GB).
# Precompile + migrate still run via deploy_tracked_app / vps-deploy.
export SKIP_RUNTIME_GATE=${SKIP_RUNTIME_GATE:-1}

echo "==> master"
zsh "$repo/OPENBSD/vps_deploy_master.sh"

echo "==> brgen"
zsh "$repo/OPENBSD/bin/vps-deploy" brgen

# Default ON for guest demo path (Live + marketplace density). Opt out: DEMO_SEED_ON_DEPLOY=0
# doas only permits dev→root; app user hop is doas sh + su -m (see RAILS/_database.sh).
if [[ ${DEMO_SEED_ON_DEPLOY:-1} == 1 ]]; then
  echo "==> bergen demo seed (posts, Live notes, listings)"
  # shellcheck disable=SC1091
  source "${repo}/RAILS/_core.sh"
  source "${repo}/RAILS/_database.sh"
  seed_demo_as_app brgen /home/brgen/app
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
