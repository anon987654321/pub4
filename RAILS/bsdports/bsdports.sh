#!/usr/bin/env zsh
# bsdports.sh — deploys the tracked bsdports Rails tree.
set -euo pipefail

APP_NAME=bsdports
APP_DIR=/home/${APP_NAME}/app
APP_PORT=47312
APP_DOMAIN=bsdports.org
SCRIPT_DIR=${0:a:h}
SRC_DIR=${SCRIPT_DIR}
SHARED_BUNDLE_CACHE=${SHARED_BUNDLE_CACHE:-/var/cache/pub4/bundle/ruby34}

. "${SCRIPT_DIR:h}/shared/deploy/@shared_functions.sh"

deploy_tracked_app "$APP_NAME"
