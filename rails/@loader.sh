#!/usr/bin/env zsh
set -euo pipefail

# Central module loader for Rails apps
# Master.yml v70.0.0 compliant - feature-based organization
# Reorganized: 2025-12-13 per ANALYSIS_COMPLETE_2025-12-13.md

SCRIPT_DIR="${0:a:h}"

# Core Infrastructure
source "${SCRIPT_DIR}/@core_database.sh"
source "${SCRIPT_DIR}/@core_dependencies.sh"
source "${SCRIPT_DIR}/@rails8_solid_stack.sh"

# Authentication & Authorization
source "${SCRIPT_DIR}/@auth_devise.sh"
source "${SCRIPT_DIR}/@auth_oauth.sh"

# Features
source "${SCRIPT_DIR}/@features_voting_comments.sh"
source "${SCRIPT_DIR}/@features_messaging_realtime.sh"
source "${SCRIPT_DIR}/@features_booking_marketplace.sh"
source "${SCRIPT_DIR}/@features_ai_langchain.sh"

# Frontend
source "${SCRIPT_DIR}/@frontend_stimulus.sh"
source "${SCRIPT_DIR}/@frontend_reflex.sh"
source "${SCRIPT_DIR}/@frontend_pwa.sh"

# Generators
source "${SCRIPT_DIR}/@generators_crud_views.sh"
source "${SCRIPT_DIR}/@generators_models.sh"

# Integrations
source "${SCRIPT_DIR}/@integrations_payment.sh"
source "${SCRIPT_DIR}/@integrations_maps.sh"
source "${SCRIPT_DIR}/@integrations_search.sh"

# Helpers
source "${SCRIPT_DIR}/@helpers_installation.sh"
source "${SCRIPT_DIR}/@helpers_routes.sh"
source "${SCRIPT_DIR}/@helpers_logging.sh"

# Main setup function - replaces setup_full_app from @common.sh
setup_full_app() {
    local app_name="$1"
    
    log "Setting up full Rails application: $app_name"
    mkdir -p "$BASE_DIR/$app_name"
    cd "$BASE_DIR/$app_name"
    
    if [ ! -f "config/application.rb" ]; then
        log "Creating new Rails application"
        rails new . --database=postgresql --skip-git --skip-bundle
    fi
    
    setup_core
    setup_postgresql
    setup_rails8_solid_stack  # Rails 8 Solid Stack (no Redis needed)
    setup_rails
}
