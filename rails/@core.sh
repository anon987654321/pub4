#!/usr/bin/env zsh
set -euo pipefail

# @core.sh - Consolidated core functionality
# Combines @core_setup.sh, @core_database.sh, @core_dependencies.sh
# Per master.yml v74.2.0 - Rails 8 + Solid Stack

# Logging
log() {
    print "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Command existence check
command_exists() {
    command -v "$1" >/dev/null 2>&1 || {
        log "ERROR: $1 is required but not installed"
        exit 1
    }
}

# Ruby environment setup
setup_ruby() {
    log "Verifying Ruby environment"
    command_exists "ruby"
    command_exists "bundle"
    
    if [ ! -f "Gemfile" ]; then
        log "Creating basic Gemfile"
        bundle init
    fi
}

# Yarn setup
setup_yarn() {
    log "Setting up Yarn and frontend assets"
    command_exists "yarn"
    
    if [ -f "package.json" ]; then
        yarn install
    fi
}

# PostgreSQL database setup
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

# Redis setup (legacy - Solid Stack preferred)
setup_redis() {
    log "Setting up Redis configuration (legacy - consider Solid Cable)"
    
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

# Rails framework setup
setup_rails() {
    log "Setting up Rails framework components"
    # Rails 8 defaults include: bootsnap, puma (remove), propshaft, solid_queue, solid_cache, solid_cable
    
    # Replace Puma with Falcon
    bundle remove puma 2>/dev/null || true
    install_gem "falcon"
    install_gem "falcon-rails"
    
    bundle install
    
    if [ ! -d "db" ]; then
        bin/rails db:create db:migrate
    fi
}

# Core application structure
setup_core() {
    log "Setting up core Rails application structure"
    setup_ruby
    setup_yarn
}

# Database migration
migrate_db() {
    log "Migrating database"
    bin/rails db:create db:migrate
}

# Database seeds setup
setup_seeds() {
    log "Setting up database seeds"
    
    if [ ! -f "db/seeds.rb" ] || [ ! -s "db/seeds.rb" ]; then
        cat > db/seeds.rb << EOF
# Seeds for ${APP_NAME}
# Create sample data for development

if Rails.env.development?
  # Add sample data creation here
  puts "Created sample data for #{Rails.env} environment"
end
EOF
    fi
}
