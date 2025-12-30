#!/usr/bin/env zsh
set -euo pipefail
# @core.sh - Core Rails 8 + Solid Stack Setup
# Combines: setup, database, dependencies
# Per: master.yml v100.0 - Rails 8 + Solid Stack
# Constants
readonly # SQLite3 requires no user config
readonly DEFAULT_PG_HOST="localhost"
readonly DEFAULT_THREAD_POOL=5  # Rails default per process  # Standard Rails connection pool size
readonly TEMPLATE_DIR="${0:a:h}/templates"
# Utility Functions
log() {
  print "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
command_exists() {
  command -v "$1" >/dev/null 2>&1 || {
    log "ERROR: $1 is required but not installed"
    return 1
  }
}
install_gem() {
  local gem_name=$1
  if ! gem list "^${gem_name}$" -i >/dev/null 2>&1; then
    log "Installing gem: ${gem_name}"
    bundle add "${gem_name}"
  fi
}
# Environment Setup
setup_ruby() {
  log "Verifying Ruby environment"
  command_exists "ruby" || return 1
  command_exists "bundle" || return 1
  if [ ! -f "Gemfile" ]; then
    log "Creating basic Gemfile"
    bundle init || { log "ERROR: Failed to initialize Gemfile"; return 1; }
  fi
}
setup_yarn() {
  log "Setting up Yarn and frontend assets"
  command_exists "yarn" || return 1
  if [ -f "package.json" ]; then
    yarn install
  fi
}
# Database Configuration
setup_database() {
  log "Setting up SQLite3 database configuration"
  if [ ! -f "config/database.yml" ]; then
    generate_database_yml
  fi
}
generate_database_yml() {
  log "Creating database configuration"
  local app_name="${APP_NAME:-myapp}"
  cat > config/database.yml << EOF
default: &default
  adapter: sqlite3
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { ${DEFAULT_THREAD_POOL} } %>
development:
  <<: *default
  database: ${app_name}_development
  username: <%= ENV.fetch("POSTGRES_USER", "${DEFAULT_PG_USER}") %>
  password: <%= ENV.fetch("POSTGRES_PASSWORD", "") %>
  host: <%= ENV.fetch("POSTGRES_HOST", "${DEFAULT_PG_HOST}") %>
test:
  <<: *default
  database: ${app_name}_test
  username: <%= ENV.fetch("POSTGRES_USER", "${DEFAULT_PG_USER}") %>
  password: <%= ENV.fetch("POSTGRES_PASSWORD", "") %>
  host: <%= ENV.fetch("POSTGRES_HOST", "${DEFAULT_PG_HOST}") %>
production:
  <<: *default
  url: <%= ENV["DATABASE_URL"] %>
EOF
}
# Rails Framework
setup_rails() {
  log "Setting up Rails framework components"
  replace_puma_with_falcon
  bundle install
  if [ ! -d "db" ]; then
    create_and_migrate_db
  fi
}
replace_puma_with_falcon() {
  log "Replacing Puma with Falcon"
  bundle remove puma 2>/dev/null || true
  install_gem "falcon"
  install_gem "falcon-rails"
}
create_and_migrate_db() {
  log "Creating and migrating database"
  bin/rails db:create db:migrate
}
# Redis (deprecated - use Solid Cable)
setup_redis() {
  log "Setting up Redis configuration (legacy - consider Solid Cable)"
  if should_configure_redis; then
    install_gem "redis"
  fi
}
should_configure_redis() {
  if [ ! -f "config/application.rb" ]; then
    return 0
  fi
  local app_config=$(<config/application.rb)
  [ "$app_config" != *redis* ]
}
# Database Seeds
setup_seeds() {
  log "Setting up database seeds"
  if needs_seeds_file; then
    generate_seeds_file
  fi
}
needs_seeds_file() {
  [ ! -f "db/seeds.rb" ] || [ ! -s "db/seeds.rb" ]
}
generate_seeds_file() {
  local app_name="${APP_NAME:-myapp}"
  cat > db/seeds.rb << EOF
# Seeds for ${app_name}
# Create sample data for development
if Rails.env.development?
  # Add sample data creation here
  puts "Created sample data for #{Rails.env} environment"
end
EOF
}
# High-Level Operations
setup_core() {
  log "Setting up core Rails application structure"
  setup_ruby || return 1
  setup_yarn || return 1
}
migrate_db() {
  log "Migrating database"
  bin/rails db:create db:migrate
}
