#!/usr/bin/env zsh
set -euo pipefail

# Core dependencies setup - Ruby, Node, Yarn
# Extracted from @core_setup.sh

setup_ruby() {
    log "Verifying Ruby environment"
    command_exists "ruby"
    command_exists "bundle"
    
    if [ ! -f "Gemfile" ]; then
        log "Creating basic Gemfile"
        bundle init
    fi
}

setup_yarn() {
    log "Setting up Yarn and frontend assets"
    command_exists "yarn"
    
    if [ -f "package.json" ]; then
        yarn install
    fi
}

setup_core() {
    log "Setting up core Rails application structure"
    setup_ruby
    setup_yarn
}
