```zsh
#!/usr/bin/env zsh
set -euo pipefail# Constants
BASE_DIR="${HOME}/rails"
APP_NAME="brgen_marketplace"
BASE_PORT=10000
PORT_RANGE=10000
MAX_ATTEMPTS=20
MIN_ATTEMPTS=10
DB_SCHEME="postgresql"
GEM_VERSIONS=(
  solidus:"~> 4.0"
  solidus_auth_devise:"~> 2.0"
  solidus_multi_vendor:"~> 1.0"
)

# Logging
log() { printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }
error_exit() { log "ERROR: $1"; exit 1; }

# Utility helpers
command_exists() { command -v "$1" >/dev/null 2>&1; }

is_port_in_use() {
  local port=$1
  if command_exists lsof; then
    lsof -i :"$port" >/dev/null 2>&1 && return 0
  elif command_exists ss; then
    ss -tuln | grep -q ":$port " && return 0
  elif command_exists netstat; then
    netstat -tuln | grep -q ":$port " && return 0
  elif zmodload zsh/net/tcp >/dev/null 2>&1; then
    ztcp -l "$port" >/dev/null 2>&1 && { ztcp -c $REPLY >/dev/null 2>&1; return 0; }
  else
    if ruby -e "require 'socket'; server=TCPServer.new('localhost',$port); server.close; exit 0" 2>/dev/null; then
      return 0
    else
      return 1
    fi
  fi
  return 1}

# Port management
get_or_create_port() {
  local port_file="${BASE_DIR}/${APP_NAME}/.app_port"
  mkdir -p "${BASE_DIR}/${APP_NAME}"

  (( port_exists = 0 ))
  if [[ -f "$port_file" ]]; then
    local saved=$(cat "$port_file")
    if is_port_in_use "$saved"; then
      APP_PORT=$saved && log "Using saved port $APP_PORT" && return 0
    fi
  fi

  local attempts=0  while (( attempts < MAX_ATTEMPTS )); do
    APP_PORT=$((BASE_PORT + RANDOM % PORT_RANGE))
    is_port_in_use "$APP_PORT" && continue
    echo "$APP_PORT" > "$port_file"
    log "Allocated port $APP_PORT"
    return 0
  done  error_exit "Unable to obtain an available port after $MAX_ATTEMPTS attempts"
}

# Dependency installation
install_gem() {
  local gem=$1 version=${2:-}
  if bundle list | grep -q "$gem"; then
    log "Gem $gem already present"
    return
  fi
  if [[ -n $version ]]; then
    bundle add "$gem" --version "$version" --without production
  else
    bundle add "$gem" --without production
  fi
  log "Installed gem $gem"
}

add_gems() {
  for pkg in "${(@)GEM_VERSIONS[@]}"; do
    IFS=':' read -r name ver <<<"$pkg"
    install_gem "$name" "$ver"
  done
}

# Database setup
setup_database_user() {
  local user="${APP_NAME}_user"
  local password=$(ruby -e 'require "securerandom"; puts SecureRandom.hex(16)')
  if ! psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$user'" >/dev/null 2>&1; then
    psql -c "CREATE USER $user WITH PASSWORD '$password' CREATEDB;" || \
      log "Warning: could not create user $user (fallback to $USER)"
    DB_USER="${DB_USER:-${USER}}"
    DB_PASSWORD="$password"
  else
    DB_USER="$user"
    DB_PASSWORD="$password"
  fi
}

setup_databases() {
  setup_database_user
  local db_user=${DB_USER:-${USER}}
  for db in "${APP_NAME}_development" "${APP_NAME}_test"; do
    if ! psql -lqt | cut -d\| -f1 | tr -d ' ' | grep -q "^$db$"; then
      createdb "$db" -O "$db_user" >/dev/null 2>&1 || createdb "$db"
      log "Database $db ready"
    else
      log "Database $db exists"
    fi
  done
}

generate_database_yml() {
  local db_user=${DB_USER:-${USER}}
  local db_pass=${DB_PASSWORD:-}
  cat > config/database.yml <<EOF
default: &default
  adapter: $DB_SCHEME
  encoding: unicode
  pool: 5
  username: $db_user  password: $db_pass
  host: localhost

development:
  <<: *default  database: ${APP_NAME}_development

test:
  <<: *default
  database: ${APP_NAME}_test

production:
  <<: *default
  database: ${APP_NAME}_production
EOF
  log "Generated config/database.yml"
}

# Rails application bootstrapping
bootstrap_app() {
  cd "$BASE_DIR" || error_exit "Cannot cd $BASE_DIR"
  if [[ ! -d "$APP_NAME" ]]; then
    log "Creating Rails app $APP_NAME"
    rails new "$APP_NAME" -d "$DB_SCHEME" || error_exit "Rails new failed"
  fi
  cd "$APP_NAME" || error_exit "Cannot cd $APP_NAME"

  setup_databases
  generate_database_yml

  add_gems
  bundle install --without production || error_exit "Bundle install failed"
  bundle exec rails generate solidus:install || error_exit "Solidus install failed"
  bundle exec rails db:migrate || error_exit "Migrations failed"
  bundle exec rails db:seed || error_exit "Seeding failed"

  cat > start_app.sh <<'EOS'
#!/usr/bin/env zsh
cd "$(dirname "$0")"
bundle exec rails server -p $APP_PORT -b 0.0.0.0
EOS
  chmod +x start_app.sh
  log "Setup complete. Run ./start_app.sh to start."
}

# Entry point
main() {
  log "Brgen Marketplace setup beginning"
  get_or_create_port
  bootstrap_app
  log "All done."
}
main "$@"
```