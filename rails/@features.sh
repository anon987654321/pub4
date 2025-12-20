#!/usr/bin/env zsh
set -euo pipefail

# @features.sh - Consolidated feature modules
# Sources all feature-specific functionality files
# Per master.yml v74.2.0 - Rails 8 + Solid Stack

SCRIPT_DIR="${0:a:h}"

# Load all feature modules
source "${SCRIPT_DIR}/@features_ai_langchain.sh"
source "${SCRIPT_DIR}/@features_booking_marketplace.sh"
source "${SCRIPT_DIR}/@features_messaging_realtime.sh"
source "${SCRIPT_DIR}/@features_voting_comments.sh"
