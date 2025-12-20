#!/usr/bin/env zsh
set -euo pipefail

# Error tracking and performance monitoring for Rails 8 apps
# Sentry for errors, Scout for performance (both have free tiers)

setup_error_tracking() {
  local service="${1:-sentry}"
  
  case "$service" in
    sentry)
      log "Setting up Sentry error tracking"
      install_gem "sentry-ruby"
      install_gem "sentry-rails"
      
      cat <<'SENTRY' > config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  config.traces_sample_rate = 0.1
  config.profiles_sample_rate = 0.1
  config.environment = Rails.env
  config.enabled_environments = %w[production staging]
end
SENTRY
      ;;
      
    rollbar)
      log "Setting up Rollbar error tracking"
      install_gem "rollbar"
      
      cat <<'ROLLBAR' > config/initializers/rollbar.rb
Rollbar.configure do |config|
  config.access_token = ENV['ROLLBAR_ACCESS_TOKEN']
  config.environment = Rails.env
  config.enabled = Rails.env.production? || Rails.env.staging?
end
ROLLBAR
      ;;
      
    honeybadger)
      log "Setting up Honeybadger error tracking"
      install_gem "honeybadger"
      
      cat <<'HONEYBADGER' > config/initializers/honeybadger.rb
Honeybadger.configure do |config|
  config.api_key = ENV['HONEYBADGER_API_KEY']
  config.env = Rails.env
end
HONEYBADGER
      ;;
  esac
  
  log "✓ Error tracking configured: $service"
}

setup_performance_monitoring() {
  local service="${1:-scout}"
  
  case "$service" in
    scout)
      log "Setting up Scout APM"
      install_gem "scout_apm"
      
      cat <<'SCOUT' > config/scout_apm.yml
common: &defaults
  name: "<%= ENV['APP_NAME'] %>"
  key: "<%= ENV['SCOUT_KEY'] %>"
  monitor: true

production:
  <<: *defaults

development:
  <<: *defaults
  monitor: false
SCOUT
      ;;
      
    skylight)
      log "Setting up Skylight"
      install_gem "skylight"
      
      cat <<'SKYLIGHT' > config/skylight.yml
authentication: <%= ENV['SKYLIGHT_AUTHENTICATION'] %>
SKYLIGHT
      ;;
      
    newrelic)
      log "Setting up New Relic"
      install_gem "newrelic_rpm"
      
      cat <<'NEWRELIC' > config/newrelic.yml
common: &default_settings
  license_key: <%= ENV['NEW_RELIC_LICENSE_KEY'] %>
  app_name: <%= ENV['APP_NAME'] %>

production:
  <<: *default_settings

development:
  <<: *default_settings
  monitor_mode: false
NEWRELIC
      ;;
  esac
  
  log "✓ Performance monitoring configured: $service"
}
