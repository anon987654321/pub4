```zsh
#!/usr/bin/env zsh
emulate -L zsh

# Brgen Marketplace setup: Multi-vendor marketplace with Solidus, unprivileged user
# Framework v37.3.2 compliant with enhanced e-commerce functionality

APP_NAME="brgen_marketplace"
BASE_DIR="${HOME}/rails"
APP_PORT=$(( 10000 + (RANDOM % 10000) ))
SECRET_KEY_BASE=$(ruby -e "require 'securerandom'; puts SecureRandom.hex(64)")

# Define helper functions
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
  log "ERROR: $1"
  exit 1
}

install_gem() {
  local gem_name="$1"
  if ! bundle list | grep -q "$gem_name"; then
    bundle add "$gem_name" --without production || error_exit "Failed to add gem: $gem_name"
  fi
}

check_port_available() {
  local port="$1"
  if command_exists lsof; then
    if lsof -i :"$port" >/dev/null 2>&1; then
      return 1
    fi
  elif command_exists netstat; then
    if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
      return 1
    fi
  elif command_exists ss; then
    if ss -tuln 2>/dev/null | grep -q ":${port} "; then
      return 1
    fi
  else
    # If no port checking tool is available, try to bind to the port
    if zmodload zsh/net/tcp 2>/dev/null; then
      ztcp -l $port 2>/dev/null
      local result=$?
      ztcp -c $REPLY 2>/dev/null
      return $result
    else
      # Last resort: try with Ruby
      ruby -e "require 'socket'; Socket.tcp_server_sockets('localhost', $port)" 2>/dev/null
      local result=$?
      [[ $result -eq 0 ]] && return 1
      return 0
    fi
  fi
  return 0
}

setup_database() {
  log "Setting up PostgreSQL database"
  if ! psql -lqt | cut -d \| -f 1 | tr -d ' ' | grep -q "^${APP_NAME}_development$"; then
    createdb "${APP_NAME}_development" || error_exit "Failed to create development database"
    log "Created development database: ${APP_NAME}_development"
  else
    log "Development database already exists: ${APP_NAME}_development"
  fi

  if ! psql -lqt | cut -d \| -f 1 | tr -d ' ' | grep -q "^${APP_NAME}_test$"; then
    createdb "${APP_NAME}_test" || error_exit "Failed to create test database"
    log "Created test database: ${APP_NAME}_test"
  else
    log "Test database already exists: ${APP_NAME}_test"
  fi
}

setup_full_app() {
  cd "${BASE_DIR}/${APP_NAME}" || error_exit "Failed to enter app directory"

  # Find available port
  while ! check_port_available $APP_PORT; do
    APP_PORT=$((APP_PORT + 1))
  done

  log "Using port: $APP_PORT"

  # Install Solidus with all components
  bundle add solidus solidus_backend solidus_frontend solidus_api solidus_auth_devise --without production || error_exit "Failed to add Solidus gems"

  # Run Solidus install generator
  bundle exec rails generate solidus:install || error_exit "Failed to run Solidus installer"

  # Run migrations
  bundle exec rails db:migrate || error_exit "Failed to run migrations"

  # Generate database.yml with dynamic configuration
  cat > config/database.yml <<EOF
default: &default
  adapter: postgresql
  encoding: unicode
  pool: 5
  username: $(whoami)
  password:
  host: localhost

development:
  <<: *default
  database: ${APP_NAME}_development

test:
  <<: *default
  database: ${APP_NAME}_test

production:
  <<: *default
  database: ${APP_NAME}_production
EOF

  log "Database configuration updated"
}

# Main execution
mkdir -p "${BASE_DIR}" || error_exit "Failed to create base directory"
cd "${BASE_DIR}" || error_exit "Failed to enter base directory"

if [[ ! -d "${APP_NAME}" ]]; then
  log "Creating new Rails app: ${APP_NAME}"
  rails new "${APP_NAME}" -d postgresql || error_exit "Failed to create Rails app"
else
  log "App directory already exists: ${APP_NAME}"
fi

setup_database
setup_full_app

log "Brgen Marketplace setup complete!"
log "App directory: ${BASE_DIR}/${APP_NAME}"
log "Development server will run on port: ${APP_PORT}"
log "Run: cd ${BASE_DIR}/${APP_NAME} && bundle exec rails server -p ${APP_PORT}"
```
