```zsh
#!/usr/bin/env zsh
emulate -L zsh

# Brgen Marketplace setup: Multi-vendor marketplace with Solidus, unprivileged user
# Framework v37.3.2 compliant with enhanced e-commerce functionality

APP_NAME="brgen_marketplace"
BASE_DIR="${HOME}/rails"
APP_PORT=$(( 10000 + (RANDOM % 10000) ))
SECRET_KEY_BASE=$(ruby -e "require 'securerandom'; puts SecureRandom.hex(64)")
PORT_FILE="${BASE_DIR}/${APP_NAME}/.app_port"

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
  local gem_version="${2:-}"
  local gem_spec="${gem_name}${gem_version:+ (${gem_version})}"

  if ! bundle list | grep -q "$gem_name"; then
    if [[ -n "$gem_version" ]]; then
      bundle add "$gem_name" --version "$gem_version" --without production || error_exit "Failed to add gem: $gem_spec"
    else
      bundle add "$gem_name" --without production || error_exit "Failed to add gem: $gem_spec"
    fi
    log "Added gem: $gem_spec"
  else
    log "Gem already installed: $gem_spec"
  fi
}

check_port_available() {
  local port="$1"

  # Try multiple methods to check port availability
  if command_exists lsof; then
    if lsof -i :"$port" >/dev/null 2>&1; then
      return 1
    fi
  elif command_exists ss; then
    if ss -tuln 2>/dev/null | grep -q ":${port} "; then
      return 1
    fi
  elif command_exists netstat; then
    if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
      return 1
    fi
  else
    # Direct socket binding check as fallback
    if zmodload zsh/net/tcp 2>/dev/null; then
      ztcp -l $port 2>/dev/null
      local result=$?
      [[ $result -eq 0 ]] && ztcp -c $REPLY 2>/dev/null
      return $result
    else
      # Ruby socket check as last resort
      if ruby -e "require 'socket';
                  begin;
                    server = TCPServer.new('localhost', $port);
                    server.close;
                    exit 0;
                  rescue Errno::EADDRINUSE;
                    exit 1;
                  end" 2>/dev/null; then
        return 0
      else
        return 1
      fi
    fi
  fi
  return 0
}

get_or_create_port() {
  mkdir -p "${BASE_DIR}/${APP_NAME}"

  if [[ -f "$PORT_FILE" ]]; then
    local saved_port=$(cat "$PORT_FILE")
    if check_port_available "$saved_port"; then
      APP_PORT="$saved_port"
      log "Using saved port: $APP_PORT"
      return 0
    else
      log "Saved port $saved_port is in use, generating new port"
    fi
  fi

  # Find an available port
  local max_attempts=10
  local attempts=0

  while [[ $attempts -lt $max_attempts ]]; do
    if check_port_available "$APP_PORT"; then
      echo "$APP_PORT" > "$PORT_FILE"
      log "Using port: $APP_PORT"
      return 0
    fi
    APP_PORT=$(( 10000 + (RANDOM % 10000) ))
    attempts=$((attempts + 1))
  done

  error_exit "Could not find an available port after $max_attempts attempts"
}

setup_database_user() {
  log "Setting up PostgreSQL user"
  local db_user="${APP_NAME}_user"
  local db_password=$(ruby -e "require 'securerandom'; puts SecureRandom.hex(16)")

  # Check if user exists
  if ! psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$db_user'" | grep -q 1; then
    if psql -c "CREATE USER $db_user WITH PASSWORD '$db_password' CREATEDB;" 2>/dev/null; then
      log "Created database user: $db_user"
    else
      log "Warning: Could not create database user $db_user (may need sudo privileges)"
      db_user="${USER}"  # Fall back to current user
    fi
  else
    log "Database user already exists: $db_user"
  fi

  # Store user info for database.yml
  export DB_USER="$db_user"
  export DB_PASSWORD="$db_password"
}

setup_database() {
  log "Setting up PostgreSQL databases"

  # Set up user first
  setup_database_user

  local db_user="${DB_USER:-${USER}}"

  # Create development database
  if ! psql -lqt | cut -d \| -f 1 | tr -d ' ' | grep -q "^${APP_NAME}_development$"; then
    if createdb "${APP_NAME}_development" -O "$db_user" 2>/dev/null; then
      log "Created development database: ${APP_NAME}_development"
    else
      # Fallback without owner specification
      if createdb "${APP_NAME}_development" 2>/dev/null; then
        log "Created development database (without owner): ${APP_NAME}_development"
      else
        error_exit "Failed to create development database: ${APP_NAME}_development"
      fi
    fi
  else
    log "Development database already exists: ${APP_NAME}_development"
  fi

  # Create test database
  if ! psql -lqt | cut -d \| -f 1 | tr -d ' ' | grep -q "^${APP_NAME}_test$"; then
    if createdb "${APP_NAME}_test" -O "$db_user" 2>/dev/null; then
      log "Created test database: ${APP_NAME}_test"
    else
      # Fallback without owner specification
      if createdb "${APP_NAME}_test" 2>/dev/null; then
        log "Created test database (without owner): ${APP_NAME}_test"
      else
        error_exit "Failed to create test database: ${APP_NAME}_test"
      fi
    fi
  else
    log "Test database already exists: ${APP_NAME}_test"
  fi
}

generate_database_yml() {
  log "Generating database configuration"
  local db_user="${DB_USER:-${USER}}"
  local db_password="${DB_PASSWORD:-}"

  cat > config/database.yml << EOF
default: &default
  adapter: postgresql
  encoding: unicode
  pool: 5
  username: $db_user
  password: $db_password
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
  log "Generated config/database.yml"
}

# Main execution
main() {
  log "Starting Brgen Marketplace setup"

  # Get or create persistent port
  get_or_create_port

  # Create application directory
  mkdir -p "$BASE_DIR"
  cd "$BASE_DIR" || error_exit "Cannot access base directory: $BASE_DIR"

  # Create new Rails application
  if [[ ! -d "$APP_NAME" ]]; then
    log "Creating new Rails application: $APP_NAME"
    rails new "$APP_NAME" -d postgresql || error_exit "Failed to create Rails application"
  fi

  cd "$APP_NAME" || error_exit "Cannot enter application directory: $APP_NAME"

  # Set up databases before generating configuration
  setup_database

  # Generate database configuration
  generate_database_yml

  # Add Solidus gems with version constraints for compatibility
  log "Adding Solidus gems"
  install_gem "solidus" "~> 4.0"
  install_gem "solidus_auth_devise" "~> 2.0"
  install_gem "solidus_multi_vendor" "~> 1.0"

  # Install gems
  log "Installing gems"
  bundle install --without production || error_exit "Failed to install gems"

  # Run Solidus installer
  log "Running Solidus installer"
  bundle exec rails generate solidus:install || error_exit "Failed to run Solidus installer"

  # Run migrations
  log "Running database migrations"
  bundle exec rails db:migrate || error_exit "Failed to run migrations"

  # Generate sample data
  log "Generating sample data"
  bundle exec rails db:seed || error_exit "Failed to seed database"

  # Create a simple startup script
  cat > start_app.sh << EOF
#!/usr/bin/env zsh
cd "\$(dirname "\$0")"
bundle exec rails server -p $APP_PORT -b 0.0.0.0
EOF
  chmod +x start_app.sh

  log "Setup completed successfully!"
  log "Application will run on port: $APP_PORT"
  log "Start the application with: ./start_app.sh"
  log "Or manually with: bundle exec rails server -p $APP_PORT -b 0.0.0.0"
}

# Run main function
main "$@"
```
