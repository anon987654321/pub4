#!/usr/bin/env zsh
# Production push, the fast path: `bin/vps-deploy all` with the CI and runtime
# gates skipped, then an optional demo seed.
#
# Usage (on vm23, as dev):
#   zsh OPENBSD/bin/vps_production_push.sh
#   DEMO_SEED_ON_DEPLOY=1 zsh OPENBSD/bin/vps_production_push.sh   # also seed brgen's guest demo
#
# One deploy path, not two. vps-deploy owns the order (master first, amber and
# bsdports last), the pull, the per-app health gate, the deploy stamp, the
# restore of shed apps and the post-restart gates; this file only chooses the
# fast flags. SKIP_CI=1 skips vps_ci.sh and SKIP_RUNTIME_GATE=1 skips the bin/ci
# runtime gate inside ${app}.sh, which is OOM-prone on 1 GB. What still runs is
# the loopback gate set vps-deploy runs after every restart.
#
# The demo seed is opt-in. A hotfix is the wrong moment to write demo content
# into production, so it takes an explicit DEMO_SEED_ON_DEPLOY=1.
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: zsh OPENBSD/bin/vps_production_push.sh   (DEMO_SEED_ON_DEPLOY=1 to seed brgen's demo)"
  exit 0
fi

repo=${PUB4_ROOT:-/home/dev/pub4}

export SKIP_CI=1
export SKIP_RUNTIME_GATE=${SKIP_RUNTIME_GATE:-1}
zsh "$repo/OPENBSD/bin/vps-deploy" all

if [[ ${DEMO_SEED_ON_DEPLOY:-0} == 1 ]]; then
  print "==> bergen demo seed (posts, Live notes, listings)"
  # doas only permits dev->root; the app user hop is doas sh + su -m (RAILS/_database.sh).
  source "${repo}/RAILS/_core.sh"
  source "${repo}/RAILS/_database.sh"
  seed_demo_as_app brgen /home/brgen/app
fi

sh "$repo/OPENBSD/bin/deploy-smoke.sh" --local || print "WARN: deploy-smoke partial"
print "==> production push complete"
