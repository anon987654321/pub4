#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Demo Rails 8 app generator – Simple CRUD with Hotwire
# Port: 10008
# Domain: demo.local (or configure as needed)

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly APP_NAME="demo"
readonly PORT=10008

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

check_prereqs() {
  require_cmd rails
  require_cmd bundler
  require_cmd lsof
  require_cmd sed
  require_cmd cp
  require_cmd cat
}

port_in_use() {
  lsof -i :"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1
}

backup_file() {
  local src=$1
  [[ -f $src ]] && cp -f "$src" "${src}.backup"
}

append_once() {
  local file=$1 marker=$2 content=$3
  grep -qF "$marker" "$file" || printf '%s\n' "$content" >>"$file"
}

create_app() {
  rails new "$APP_NAME" \
    --database=postgresql \
    --css=tailwind \
    --javascript=importmap ||
    die "Failed to create Rails app"
}

write_database_yml() {
  cat > config/database.yml <<EOF
default: &default
  adapter: postgresql
  encoding: unicode
  pool: 5

development:
  <<: *default
  database: ${APP_NAME}_development

test:
  <<: *default
  database: ${APP_NAME}_test

production:
  <<: *default
  database: ${APP_NAME}_production
  username: ${APP_NAME}
  password: <%= ENV["${APP_NAME^^}_DATABASE_PASSWORD"] %>
EOF
}

configure_solid_gems() {
  local application_rb="config/application.rb"
  backup_file "$application_rb"

  append_once "$application_rb" "config.solid_queue" $'\n# Solid Queue configuration\nconfig.solid_queue.connects_to = { database: { writing: :primary } }'
  append_once "$application_rb" "config.solid_cache" $'\n# Solid Cache configuration\nconfig.solid_cache.connects_to = { database: { writing: :primary } }'
  append_once "$application_rb" "config.solid_cable" $'\n# Solid Cable configuration\nconfig.solid_cable.connects_to = { database: { writing: :primary } }'
}

inject_layout_wrapper() {
  local layout_file="app/views/layouts/application.html.erb"
  [[ -f $layout_file ]] || return

  sed -i.bak '/<body>/a\
    <div class="container mx-auto px-4 py-8">\
      <h1 class="text-3xl font-bold mb-6">Demo App</h1>\
      <%= yield %>\
    </div>' "$layout_file"
  rm -f "${layout_file}.bak"
}

start_server() {
  bin/rails server -p "$PORT" -d ||
    die "Failed to start Rails server"
  printf 'Demo app created successfully!\nApp is running on http://localhost:%s\nStop the server with: bin/rails server -p %s -d -s\n' "$PORT" "$PORT"
}

main() {
  check_prereqs

  local app_dir="${SCRIPT_DIR}/${APP_NAME}"
  [[ -d $app_dir ]] && die "Directory $app_dir already exists"
  port_in_use && die "Port $PORT is already in use"

  create_app
  cd "$APP_NAME"

  backup_file config/database.yml
  write_database_yml

  bin/rails db:create || die "Failed to create databases"

  bundle add solid_queue solid_cache solid_cable || die "Failed to add Solid* gems"
  configure_solid_gems

  bin/rails generate scaffold Post title:string content:text --no-jbuilder
  bin/rails db:migrate || die "Failed to run migrations"

  cat > config/routes.rb <<'EOF'
Rails.application.routes.draw do
  resources :posts
  root 'posts#index'
end
EOF

  inject_layout_wrapper
  start_server
}

main "$@"
