#!/usr/bin/env zsh
# Deployment scripts are operator-owned entrypoints, not root-executed payloads.
# The canonical supervisor runs as dev and delegates fixed privileged actions.
if [[ $(id -u) -eq 0 ]]; then
  print -u2 "mrdamascy.sh: refusing to run checkout code as root; use zsh OPENBSD/bin/vps-deploy mrdamascy"
  exit 2
fi
# mrdamascy.sh — deploys the tracked mrdamascy Rails tree (the mrd.brgen.no demo).
set -euo pipefail

APP_NAME=mrdamascy
APP_DIR=/home/${APP_NAME}/app
APP_PORT=47314
APP_DOMAIN=mrd.brgen.no
SCRIPT_DIR=${0:a:h}
SRC_DIR=${SCRIPT_DIR}
. "${SCRIPT_DIR:h:h}/OPENBSD/lib/ruby_select.sh"
SHARED_BUNDLE_CACHE=${SHARED_BUNDLE_CACHE:-/var/cache/pub4/bundle/${RUBY_CACHE_KEY}}

. "${SCRIPT_DIR:h}/_deploy.sh"

deploy_tracked_app "$APP_NAME"
