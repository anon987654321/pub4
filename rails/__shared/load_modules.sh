#!/usr/bin/env zsh
set -euo pipefail

# Central module loader - consolidated per master.json v44.3.0
SCRIPT_DIR="${0:a:h}"

# Core infrastructure
[[ -f "${SCRIPT_DIR}/@core_setup.sh" ]] && source "${SCRIPT_DIR}/@core_setup.sh"
[[ -f "${SCRIPT_DIR}/@rails8_stack.sh" ]] && source "${SCRIPT_DIR}/@rails8_stack.sh"

# UI/Frontend
[[ -f "${SCRIPT_DIR}/@stimulus_controllers.sh" ]] && source "${SCRIPT_DIR}/@stimulus_controllers.sh"
[[ -f "${SCRIPT_DIR}/@pwa_setup.sh" ]] && source "${SCRIPT_DIR}/@pwa_setup.sh"
[[ -f "${SCRIPT_DIR}/@reflex_patterns.sh" ]] && source "${SCRIPT_DIR}/@reflex_patterns.sh"
[[ -f "${SCRIPT_DIR}/@view_generators.sh" ]] && source "${SCRIPT_DIR}/@view_generators.sh"

# Feature domains
[[ -f "${SCRIPT_DIR}/@social_features.sh" ]] && source "${SCRIPT_DIR}/@social_features.sh"
[[ -f "${SCRIPT_DIR}/@chat_features.sh" ]] && source "${SCRIPT_DIR}/@chat_features.sh"
[[ -f "${SCRIPT_DIR}/@marketplace_features.sh" ]] && source "${SCRIPT_DIR}/@marketplace_features.sh"
[[ -f "${SCRIPT_DIR}/@ai_features.sh" ]] && source "${SCRIPT_DIR}/@ai_features.sh"

# Utilities
[[ -f "${SCRIPT_DIR}/@route_helpers.sh" ]] && source "${SCRIPT_DIR}/@route_helpers.sh"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
