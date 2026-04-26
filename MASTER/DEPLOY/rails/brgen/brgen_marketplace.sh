#!/usr/bin/env sh
set -euo pipefail

#─────────────────────────────────────────────────────────────────────────────
# Brgen Marketplace deployment helper
#─────────────────────────────────────────────────────────────────────────────

# Configuration
BASE_DIR="${HOME}/rails"
APP_NAME="brgen_marketplace"
BASE_PORT=10000
PORT_RANGE=10000
MAX_ATTEMPTS=20
DB_SCHEME="postgresql"
GEM_VERSIONS='solidus:~>4.0 solidus_auth_devise:~>2.0 solidus_multi_vendor:~>1.0'

# Logging
log()    { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
error()  { log "ERROR: $*"; exit 1; }

# Helpers
command_exists() { command -v "$1" >/dev/null 2>&1; }

port_in_use() {
  p=$1
  if command_exists lsof; then
    lsof -i :"$p" >/dev/null 2>&1 && return 0
  elif command_exists ss; then
    ss -tuln | grep -qE ":$p[[:space:]]" && return 0
  elif command_exists netstat; then
    netstat -tuln | grep -qE ":$p[[:space:]]" && return 0
  else
    ruby -e "require 'socket'; TCPServer.new('127.0.0.1',$p).close" >/dev/null 2>&1 && return 1 || return 0
  fi
  return 1
}

# Port allocation
get_or_create_port() {
  port_file="${BASE_DIR}/${APP_NAME}/.app_port"
  mkdir -p "$(dirname "$port_file")"

  if [ -f "$port_file" ]; then
    saved=$(cat "$port_file")
    if ! port_in_use "$saved"; then
      APP_PORT=$saved
      log "Reusing saved port $APP_PORT"
      return
    fi
  fi

  attempt=0
  while [ $attempt -lt $MAX_ATTEMPTS ]; do
    rand=$(( (RANDOM << 15) | RANDOM ))
    APP_PORT=$(( BASE_PORT + (rand % PORT_RANGE) ))
    if ! port_in_use "$APP_PORT"; then
      printf '%s\n' "$APP_PORT" >"$port_file"
      log "Allocated new port $APP_PORT"
      return
    fi
    attempt=$((attempt + 1))
  done
  error "Failed to obtain a free port after $MAX_ATTEMPTS attempts"
}

# Gem management
install_gem() {
  gem=$1 version=$2
  if bundle list | grep -q "$gem"; then
    log "Gem $gem already installed"
    return
  fi
  if [ -n "$version" ]; then
    bundle add "$gem" --version "$version" --without production
  else
    bundle add "$gem" --without production
  fi
  log "Added gem $gem"
}

add_gems() {
  for pair in $GEM_VERSIONS; do
    IFS=':' read -r name ver <<EOF
$pair
EOF
    install_gem "$name" "$ver"
  done
}

# Database handling
setup_database_user() {
  user="${APP_NAME}_user"
  if ! psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${user}'" | grep -q 1; then
    pw=$(ruby -e 'require "securerandom"; puts SecureRandom.hex(16)')
    if psql -c "CREATE USER ${user} WITH PASSWORD '${pw}' CREATEDB;" >/dev/null 2>&1; then
      DB_USER=$user DB_PASSWORD=$pw
    else
      log "Warning: could not create ${user}, falling back to $USER"
      DB_USER=$USER DB_PASSWORD=
    fi
  else
    DB_USER=$user DB_PASSWORD=
  fi
  export DB_USER DB_PASSWORD
}

setup_databases() {
  setup_database_user
  owner="${DB_USER:-$USER}"
  for db in "${APP_NAME}_development" "${APP_NAME}_test"; do
    if ! psql -lqt | awk -F'|' '{gsub(/ /,"",$1);print $1}' | grep -qx "$db"; then
      createdb "$db" -O "$owner" >/dev/null 2>&1 || createdb "$db" >/dev/null 2>&1
      log "Created database $db"
    else
      log "Database $db already exists"
    fi
  done
}

generate_database_yml() {
  cat >config/database.yml <<EOF
default: &default
  adapter: ${DB_SCHEME}
  encoding: unicode
  pool: 5
  username: ${DB_USER}
  password: ${DB_PASSWORD}
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
  log "Wrote config/database.yml"
}

# Rails bootstrapping
bootstrap_app() {
  cd "$BASE_DIR" || error "Cannot cd $BASE_DIR"

  if [ ! -d "$APP_NAME" ]; then
    log "Creating Rails app $APP_NAME"
    rails new "$APP_NAME" -d "$DB_SCHEME" || error "rails new failed"
  fi

  cd "$APP_NAME" || error "Cannot cd $APP_NAME"

  setup_databases
  generate_database_yml

  add_gems
  bundle install --without production || error "bundle install failed"
  bundle exec rails generate solidus:install || error "solidus install failed"
  bundle exec rails db:migrate || error "migrations failed"
  bundle exec rails db:seed || error "seeding failed"

  cat >start_app.sh <<'EOS'
#!/usr/bin/env sh
set -euo pipefail
cd "$(dirname "$0")"
exec bundle exec rails server -p "$APP_PORT" -b 0.0.0.0
EOS
  chmod +x start_app.sh
  log "Setup complete – run ./start_app.sh"
}

# Entry point
log "Starting Brgen Marketplace deployment"
get_or_create_port
bootstrap_app
log "All done."