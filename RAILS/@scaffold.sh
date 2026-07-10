#!/usr/bin/env zsh
# @scaffold.sh — bootstrap a brand-new Rails app (rails new, Solid stack,
# auth, storage, action text, security tools, production config). Distinct
# from deploying an already-tracked app — see @deploy.sh for that.
# Source this file; do not execute directly. Requires @core.sh, @bundle.sh sourced first.

create_rails_app() {
  local app_dir=$1
  local app_name=${app_dir:t:h}
  mkdir -p "${app_dir:h}"
  if [[ ! -f "${app_dir}/config/application.rb" ]]; then
    log "Creating Rails 8 app at $app_dir"
    rails new "$app_dir" \
      --database=sqlite3 \
      --asset-pipeline=propshaft \
      --javascript=importmap \
      --skip-git \
      --skip-test \
      --skip-bundle
    # Bootstrap gems from amber to avoid OOM on fresh bundle install
    local bundle_home="/home/${app_dir:h:t}/.bundle"
    if [[ ! -d "${bundle_home}/gems" ]]; then
      log "Bootstrapping gems from amber"
      mkdir -p "${bundle_home}"
      ${_PRIV} mkdir -p "${bundle_home}/gems" "${bundle_home}/cache"
      ${_PRIV} openrsync -a /home/amber/.bundle/gems/ "${bundle_home}/gems/"
      ${_PRIV} openrsync -a /home/amber/.bundle/cache/ "${bundle_home}/cache/" 2>/dev/null || true
    fi
    mkdir -p "${app_dir}/.bundle"
    print "---\nBUNDLE_PATH: \"${bundle_home}/gems\"" > "${app_dir}/.bundle/config"
    cp /home/amber/app/Gemfile.lock "${app_dir}/Gemfile.lock"
  fi
  cd "$app_dir"
  log_ok "Working in: $app_dir"
}

install_solid_stack() {
  log "Installing Solid Cache / Queue / Cable"
  add_gem solid_cache
  add_gem solid_queue
  add_gem solid_cable
  bin/rails solid_cache:install 2>/dev/null || true
  bin/rails solid_queue:install 2>/dev/null || true
  bin/rails solid_cable:install 2>/dev/null || true
  log_ok "Solid stack installed"
}

install_auth() {
  if [[ ! -f app/models/session.rb ]]; then
    log "Generating Rails 8 authentication"
    bin/rails generate authentication
    bin/rails db:migrate
  else
    log_ok "Authentication already generated"
  fi
}

install_active_storage() {
  if [[ -z $(print db/migrate/*create_active_storage*(N)) ]]; then
    log "Installing Active Storage"
    bin/rails active_storage:install
    bin/rails db:migrate
  else
    log_ok "Active Storage already installed"
  fi
}

install_action_text() {
  if [[ -z $(print db/migrate/*create_action_text*(N)) ]]; then
    log "Installing Action Text"
    bin/rails action_text:install
    bin/rails db:migrate
  else
    log_ok "Action Text already installed"
  fi
}

install_security_tools() {
  add_gem_group "development,test" brakeman rubocop-rails-omakase
  log_ok "Security tools added"
}

configure_production() {
  local cfg=config/environments/production.rb
  local text
  text=$(<"$cfg")
  [[ $text == *"assume_ssl"* ]] || print '  config.assume_ssl = true' >> "$cfg"
  [[ $text == *"solid_cache"* ]] || print '  config.cache_store = :solid_cache_store' >> "$cfg"
  log_ok "Production config updated"
}
