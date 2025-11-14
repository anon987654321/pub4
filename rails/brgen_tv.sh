#!/usr/bin/env zsh
set -euo pipefail

readonly VERSION="1.0.0"

SCRIPT_DIR="${0:a:h}"

source "${SCRIPT_DIR}/__shared/@common.sh"

APP_DIR="/home/brgen/app"

cd "$APP_DIR"

log "Brgen TV setup complete - video streaming, AI-generated content"

