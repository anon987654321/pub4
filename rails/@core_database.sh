#!/usr/bin/env zsh
set -euo pipefail
# Database setup - PostgreSQL configuration
# Extracted from @core_setup.sh
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
