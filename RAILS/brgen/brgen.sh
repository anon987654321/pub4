#!/usr/bin/env zsh
# brgen.sh — deploys the tracked Brgen Rails tree.
set -euo pipefail

APP_NAME=brgen
APP_DIR=/home/${APP_NAME}/app
APP_PORT=38182
APP_DOMAIN=brgen.no
SCRIPT_DIR=${0:a:h}
SRC_DIR=${SCRIPT_DIR}
. "${SCRIPT_DIR:h:h}/OPENBSD/lib/ruby_select.sh"
SHARED_BUNDLE_CACHE=${SHARED_BUNDLE_CACHE:-/var/cache/pub4/bundle/${RUBY_CACHE_KEY}}

. "${SCRIPT_DIR:h}/_deploy.sh"

deploy_tracked_app "$APP_NAME"
