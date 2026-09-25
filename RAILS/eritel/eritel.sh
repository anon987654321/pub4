#!/usr/bin/env zsh
set -euo pipefail

APP_NAME=eritel
APP_DIR=/home/eritel/app
APP_PORT=49173
APP_DOMAIN=${ERITEL_APP_DOMAIN:-eritel.example.invalid}
SCRIPT_DIR=${0:a:h}

# Reference deployment only. This does not add the service to pub4 inventory.
. "${SCRIPT_DIR:h}/../_deploy.sh"

deploy_tracked_app "$APP_NAME"
