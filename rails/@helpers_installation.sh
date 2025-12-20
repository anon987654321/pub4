#!/usr/bin/env zsh
set -euo pipefail

# Installation helpers - extracted from @core_setup.sh and @common.sh
# Master.yml v70.0.0 compliant

command_exists() {
    command -v "$1" >/dev/null 2>&1 || {
        log "ERROR: $1 is required but not installed"
        exit 1
    }
}

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

install_yarn_package() {
    local package_name="$1"
    
    if [[ -f "package.json" ]]; then
        local pkg_json=$(<package.json)
        if [[ "$pkg_json" != *"\"$package_name\""* ]]; then
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

install_stimulus_component() {
    local component_name="$1"
    log "Installing Stimulus component: $component_name"
    yarn add "@stimulus-components/${component_name}"
    log "Stimulus component installed: $component_name"
    log "Register in app/javascript/controllers/index.js"
}
