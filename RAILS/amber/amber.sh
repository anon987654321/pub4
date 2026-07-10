#!/usr/bin/env zsh
# amber.sh — deploys the tracked Amber Rails tree at app/.
set -euo pipefail

APP_NAME=amber
APP_DIR=/home/${APP_NAME}/app
APP_PORT=61352
APP_DOMAIN=amber.brgen.no
SCRIPT_DIR=${0:a:h}
SRC_DIR=${SCRIPT_DIR}
SHARED_BUNDLE_CACHE=${SHARED_BUNDLE_CACHE:-/var/cache/pub4/bundle/ruby34}

. "${SCRIPT_DIR:h}/@deploy.sh"

deploy_tracked_app "$APP_NAME"
