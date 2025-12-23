#!/usr/bin/env zsh
set -euo pipefail
# @integrations.sh - Consolidated integration modules
# Sources all integration-specific functionality files
# Per master.yml v74.2.0 - Rails 8 + Solid Stack
SCRIPT_DIR="${0:a:h}"
# Load all integration modules
source "${SCRIPT_DIR}/@integrations_chat_actioncable.sh"
source "${SCRIPT_DIR}/@integrations_search.sh"
