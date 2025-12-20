#!/usr/bin/env zsh
set -euo pipefail

# @helpers.sh - Consolidated helper functions
# Merged: @helpers_installation.sh, @helpers_logging.sh, @helpers_routes.sh, @route_helpers.sh
# Per master.yml v101.0

check_app_exists() {
    local app_name="$1"
    local marker_file="$2"
    local base_dir="${BASE_DIR:-/home/dev/rails}"
    
    if [[ -f "${base_dir}/${app_name}/${marker_file}" ]]; then
        print "${app_name} already exists, skipping"
        return 0
    fi
    return 1
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

add_routes_block() {
    local routes_block="$1"
    local routes_file="config/routes.rb"
    
    local routes_lines=("${(@f)$(<$routes_file)}")
    {
        print -l "${routes_lines[1,-2]}"
        print -r -- "$routes_block"
        print "end"
    } > "$routes_file"
}

commit() {
    local message="${1:-Update application setup}"
    log "Committing changes: $message"
    
    if [ -d ".git" ]; then
        git add -A
        git commit -m "$message" || log "Nothing to commit"
    else
        log "Not a git repository, skipping commit"
    fi
}

migrate_db() {
    log "Migrating database"
    bin/rails db:create db:migrate
}

setup_seeds() {
    log "Setting up database seeds"
    
    if [ ! -f "db/seeds.rb" ] || [ ! -s "db/seeds.rb" ]; then
        cat > db/seeds.rb << EOF
# Seeds for ${APP_NAME}
# Create sample data for development

if Rails.env.development?
  # Add sample data creation here
  puts "Created sample data for \#{Rails.env} environment"
end
EOF
    fi
}
