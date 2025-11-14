#!/usr/bin/env zsh
set -euo pipefail

# Core Rails setup functions - database, dependencies, basic structure
# Extracted from @common.sh per master.json:file_organization

log() {
    print "[$(date '+%Y-%m-%d %H:%M:%S')] $*"

}

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

setup_postgresql() {
    log "Setting up PostgreSQL database configuration"

    if [ ! -f "config/database.yml" ]; then
        log "Creating database configuration"

        cat > config/database.yml << EOF

default: &default

  adapter: postgresql

  encoding: unicode

  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

development:
  <<: *default

  database: ${APP_NAME}_development

  username: <%= ENV.fetch("POSTGRES_USER", "dev") %>

  password: <%= ENV.fetch("POSTGRES_PASSWORD", "") %>

  host: <%= ENV.fetch("POSTGRES_HOST", "localhost") %>

test:
  <<: *default

  database: ${APP_NAME}_test

  username: <%= ENV.fetch("POSTGRES_USER", "dev") %>

  password: <%= ENV.fetch("POSTGRES_PASSWORD", "") %>

  host: <%= ENV.fetch("POSTGRES_HOST", "localhost") %>

production:
  <<: *default

  url: <%= ENV["DATABASE_URL"] %>

EOF

    fi

}

setup_redis() {
    log "Setting up Redis configuration"

    if [[ -f "config/application.rb" ]]; then
        local app_config=$(<config/application.rb)

        if [[ "$app_config" != *redis* ]]; then

            log "Configuring Redis connection"

            install_gem "redis"

        fi

    else

        log "Configuring Redis connection"

        install_gem "redis"

    fi

}

setup_rails() {
    log "Setting up Rails framework components"

    install_gem "bootsnap"
    install_gem "puma"

    install_gem "sprockets-rails"

    bundle install
    if [ ! -d "db" ]; then
        bin/rails db:create db:migrate

    fi

}

setup_core() {
    log "Setting up core Rails application structure"

    setup_ruby
    setup_yarn

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

