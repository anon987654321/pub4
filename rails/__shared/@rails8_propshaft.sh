#!/usr/bin/env zsh
set -euo pipefail

# Rails 8 Propshaft Asset Pipeline Configuration
# Replaces Sprockets with modern, faster asset management

setup_propshaft() {
  log "Setting up Propshaft asset pipeline"
  
  install_gem "propshaft"
  
  cat > config/initializers/propshaft.rb << 'EOF'
Rails.application.configure do
  # Propshaft configuration for Rails 8
  config.assets.paths << Rails.root.join("app/components")
  config.assets.paths << Rails.root.join("app/javascript")
  
  # Exclude source maps in production
  config.assets.excluded_patterns << /\.map$/
  
  # Compile additional assets
  config.assets.precompile += %w[application.css application.js]
end
EOF

  log "✓ Propshaft configured"
}

setup_asset_optimization() {
  log "Setting up asset optimization"
  
  cat >> config/environments/production.rb << 'EOF'

  # Asset optimization for production
  config.assets.compile = false
  config.assets.digest = true
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?
  
  # Cache control for assets
  config.public_file_server.headers = {
    'Cache-Control' => 'public, max-age=31536000'
  }
EOF

  log "✓ Asset optimization configured"
}

setup_propshaft_full() {
  setup_propshaft
  setup_asset_optimization
  log "✓ Propshaft asset pipeline ready"
}
