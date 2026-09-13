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
# rcctl and loopback /up for every app and relayd, from the one smoke script
# that reads nothing but its own list; a failure warns rather than aborts
# because the deploys above have already landed.
sh "$repo/OPENBSD/bin/deploy-smoke.sh" --local || echo "WARN: deploy-smoke --local failed"
ruby "$repo/MASTER/web/script/probe_http" 2>/dev/null || true

echo "==> production push complete"
