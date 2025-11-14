#!/usr/bin/env zsh
set -euo pipefail

# Rails 8 Solid Stack - Queue, Cache, Cable (replaces Redis)
# Per master.json:rails8

setup_solid_queue() {
    log "Setting up Solid Queue for background jobs"

    install_gem "solid_queue"
    if [ ! -f "config/queue.yml" ]; then
        bin/rails generate solid_queue:install

    fi

}

setup_solid_cache() {
    log "Setting up Solid Cache"

    install_gem "solid_cache"
    if [ ! -f "db/migrate/*_create_solid_cache_tables.rb" ]; then

        bin/rails generate solid_cache:install

    fi

    if [ ! -f "config/initializers/solid_cache.rb" ]; then
        cat > config/initializers/solid_cache.rb << EOF

Rails.application.configure do

  config.cache_store = :solid_cache_store

end

EOF

    fi

}

setup_solid_cable() {
    log "Setting up Solid Cable for ActionCable"

    install_gem "solid_cable"
    if [ ! -f "db/migrate/*_create_solid_cable_tables.rb" ]; then
        bin/rails generate solid_cable:install

    fi

    if [ ! -f "config/cable.yml" ]; then
        cat > config/cable.yml << EOF

development:

  adapter: solid_cable

  connects_to:

    database:

      writing: cable

test:
  adapter: test

production:
  adapter: solid_cable

  connects_to:

    database:

      writing: cable

EOF

    fi

}

setup_rails8_authentication() {
    log "Setting up Rails 8 built-in authentication"

    if [ ! -f "app/models/session.rb" ]; then
        bin/rails generate authentication

    fi

    log "Rails 8 authentication installed. User sessions, password resets included."
}

setup_rails8_solid_stack() {
    log "Setting up full Rails 8 Solid Stack (Queue, Cache, Cable)"

    setup_solid_queue
    setup_solid_cache

    setup_solid_cable

    log "Rails 8 Solid Stack complete - Redis-free operation enabled"
}

