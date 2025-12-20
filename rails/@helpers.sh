#!/usr/bin/env zsh
set -euo pipefail

# @helpers.sh - Consolidated helper functions
# Combines @helpers_installation.sh, @helpers_logging.sh, @helpers_routes.sh
# Per master.yml v74.2.0 - Rails 8 + Solid Stack

# Idempotency check - skip if app already generated
check_app_exists() {
    local app_name="$1"
    local marker_file="$2"  # e.g., "app/models/blog.rb"
    # Use BASE_DIR if set, otherwise fallback to default Rails location
    local base_dir="${BASE_DIR:-/home/dev/rails}"
    
    if [[ -f "${base_dir}/${app_name}/${marker_file}" ]]; then
        print "${app_name} already exists, skipping"
        return 0  # App exists
    fi
    return 1  # App does not exist
}

# Gem installation helper
install_gem() {
    local gem_name="$1"
    local bundle_output=$(bundle list 2>/dev/null)
    
    if [[ "$bundle_output" != *"  * $gem_name "* ]]; then
        log "Installing gem: $gem_name"
        bundle add "$gem_name"
    else
        log "Gem already installed: $gem_name"
    fi
}

# Yarn package installation helper
install_yarn_package() {
    local package_name="$1"
    
    if [[ -f "package.json" ]]; then
        local pkg_json=$(<package.json)
        if [[ "$pkg_json" != *""$package_name""* ]]; then
            log "Installing yarn package: $package_name"
            yarn add "$package_name"
        else
            log "Yarn package already installed: $package_name"
        fi
    else
        log "Installing yarn package: $package_name"
        yarn add "$package_name"
    fi
}

# Stimulus component installation
install_stimulus_component() {
    local component_name="$1"
    log "Installing Stimulus component: $component_name"
    yarn add "@stimulus-components/${component_name}"
    log "Stimulus component installed: $component_name"
    log "Register in app/javascript/controllers/index.js"
}

# Route manipulation using pure zsh
add_routes_block() {
    local routes_block="$1"
    local routes_file="config/routes.rb"
    
    # Read all lines, remove last 'end', append routes, add 'end'
    local routes_lines=("${(@f)$(<$routes_file)}")
    {
        print -l "${routes_lines[1,-2]}"
        print -r -- "$routes_block"
        print "end"
    } > "$routes_file"
}

# Git commit helper
commit() {
    local message="${1:-Update application setup}"
    log "Committing changes: $message"
    
    # Only commit if in git repository
    if [ -d ".git" ]; then
        git add -A
        git commit -m "$message" || log "Nothing to commit"
    else
        log "Not a git repository, skipping commit"
    fi
}
