#!/usr/bin/env zsh
set -euo pipefail

# Devise + devise-guests setup - extracted from duplicated code
# Used by: amber.sh, blognet.sh, brgen.sh (and 5 others)

setup_devise_guests() {
  local app_name="${1:-app}"
  
  log "Setting up Devise + devise-guests for $app_name"
  
  # Install gems
  install_gem "devise"
  install_gem "devise-guests"
  
  # Check if already installed
  [[ -f "config/initializers/devise.rb" ]] && {
    log "✓ Devise already configured"
    return 0
  }
  
  # Generate Devise
  bin/rails generate devise:install
  bin/rails generate devise User
  
  # Generate devise-guests
  bin/rails generate devise_guests:install
  
  # Configure Devise initializer for production
  cat >> config/initializers/devise.rb << 'EOF'

# Production config
config.mailer_sender = ENV.fetch("DEVISE_MAILER_SENDER", "noreply@example.com")
config.secret_key = ENV["DEVISE_SECRET_KEY"] if Rails.env.production?
EOF
  
  # Add to User model if not already present
  local user_model="app/models/user.rb"
  if [[ -f "$user_model" ]]; then
    local content=$(<"$user_model")
    
    # Pure zsh: check if guest already configured
    [[ "$content" != *"devise_guest"* ]] && {
      # Add guest support after devise line
      content="${content//devise :database_authenticatable/devise :database_authenticatable\n  devise :guest}"
      print -r -- "$content" > "$user_model"
    }
  fi
  
  log "✓ Devise + devise-guests configured"
}

setup_devise_standard() {
  local app_name="${1:-app}"
  
  log "Setting up Devise (standard) for $app_name"
  
  install_gem "devise"
  
  [[ -f "config/initializers/devise.rb" ]] && {
    log "✓ Devise already configured"
    return 0
  }
  
  bin/rails generate devise:install
  bin/rails generate devise User
  
  # Production config
  cat >> config/initializers/devise.rb << 'EOF'

config.mailer_sender = ENV.fetch("DEVISE_MAILER_SENDER", "noreply@example.com")
config.secret_key = ENV["DEVISE_SECRET_KEY"] if Rails.env.production?
EOF
  
  log "✓ Devise configured"
}

# Generate Devise views (optional)
generate_devise_views() {
  bin/rails generate devise:views
  log "✓ Devise views generated"
}

# Add Devise routes helper
add_devise_routes() {
  local routes_file="config/routes.rb"
  local content=$(<"$routes_file")
  
  # Pure zsh: check if devise_for already exists
  [[ "$content" == *"devise_for :users"* ]] && return 0
  
  # Add before final 'end'
  local -a lines=("${(@f)content}")
  {
    print -l "${lines[1,-2]}"
    print "  devise_for :users"
    print "end"
  } > "$routes_file"
  
  log "✓ Devise routes added"
}
