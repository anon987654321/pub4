#!/usr/bin/env zsh
# hjerterom.sh — deploys the tracked Hjerterom Rails tree.
set -euo pipefail

APP_NAME=hjerterom
APP_DIR=/home/${APP_NAME}/app
APP_PORT=38891
APP_DOMAIN=hjerterom.brgen.no
SCRIPT_DIR=${0:a:h}
SRC_DIR=${SCRIPT_DIR}
SHARED_BUNDLE_CACHE=${SHARED_BUNDLE_CACHE:-/var/cache/pub4/bundle/ruby34}

. "${SCRIPT_DIR:h}/@deploy.sh"

deploy_tracked_app "$APP_NAME"
