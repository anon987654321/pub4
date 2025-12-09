#!/usr/bin/env zsh
set -euo pipefail

# Rails 8 Solid Stack - Modern setup for Redis-free operation

setup_solid_queue() {
  log "Setting up Solid Queue (background jobs)"
  install_gem "solid_queue"
  
  if [[ ! -f "config/queue.yml" ]]; then
    bin/rails generate solid_queue:install
  fi
  
  # Configure for production
  cat >> config/application.rb << 'EOF'

    config.active_job.queue_adapter = :solid_queue
EOF
  
  log "✓ Solid Queue configured"
}

setup_solid_cache() {
  log "Setting up Solid Cache"
  install_gem "solid_cache"
  
  if [[ ! -f "config/initializers/solid_cache.rb" ]]; then
    bin/rails generate solid_cache:install
    
    cat > config/initializers/solid_cache.rb << 'EOF'
Rails.application.configure do
  config.cache_store = :solid_cache_store
end
EOF
  fi
  
  log "✓ Solid Cache configured"
}

setup_solid_cable() {
  log "Setting up Solid Cable (WebSockets)"
  install_gem "solid_cable"
  
  if [[ ! -f "config/cable.yml" ]]; then
    bin/rails generate solid_cable:install
    
    cat > config/cable.yml << 'EOF'
development:
  adapter: solid_cable

test:
  adapter: test

production:
  adapter: solid_cable
EOF
  fi
  
  log "✓ Solid Cable configured"
}

setup_rails8_authentication() {
  log "Setting up Rails 8 authentication"
  
  if [[ ! -f "app/models/session.rb" ]]; then
    bin/rails generate authentication
  fi
  
  log "✓ Rails 8 authentication installed"
}

setup_rails8_solid_stack() {
  log "Installing Rails 8 Solid Stack"
  
  setup_solid_queue
  setup_solid_cache
  setup_solid_cable
  
  # Run migrations
  bin/rails db:migrate || true
  
  log "✓ Rails 8 Solid Stack complete (Redis-free)"
}
}

