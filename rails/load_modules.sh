#!/usr/bin/env zsh
set -euo pipefail
# Central module loader - consolidated per master.yml v74.2.0
# Use @shared_functions.sh instead - this file is kept for backward compatibility
SCRIPT_DIR="${0:a:h}"
# Load the consolidated shared functions
source "${SCRIPT_DIR}/@shared_functions.sh"
