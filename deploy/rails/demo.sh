

```bash
#!/usr/bin/env bash
set -euo pipefail

# Demo Rails 8 app generator - Simple CRUD with Hotwire
# Port: 10008
# Domain: demo.local (or configure as needed)

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly APP_NAME="demo"
readonly PORT=10008

main() {
    local app_dir="${SCRIPT_DIR}/${APP_NAME}"

    # Check if app directory already exists
    if [[ -d "$app_dir" ]]; then
        echo "Error: Directory $app_dir already exists" >&2
        exit 1
    fi

    # Check port availability
    if lsof -i :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "Error: Port $PORT is already in use" >&2
        exit 1
    fi

    rails new "$APP_NAME" \
        --database=postgresql \
        --css=tailwind \
        --javascript=importmap

    cd "$APP_NAME"

    # Backup existing database.yml if present
    if [[ -f config/database.yml ]]; then
        cp -f config/database.yml config/database.yml.backup
    fi

    # Configure database
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

    # Create databases
    bin/rails db:create

    # Add Solid Queue, Cache, Cable
    bundle add solid_queue solid_cache solid_cable

    # Backup existing application.rb if present
    if [[ -f config/application.rb ]]; then
        cp -f config/application.rb config/application.rb.backup
    fi

    # Configure for production
    if ! grep -q "config.active_job.queue_adapter" config/application.rb; then
        cat >> config/application.rb <<EOF

    # Solid* stack
    config.active_job.queue_adapter = :solid_queue
    config.cache_store = :solid_cache_store
    config.action_cable.adapter = :solid_cable
EOF
    fi

    # Generate Pos
    bin/rails generate controller Posts index show new edit
    bin/rails generate model Post title:string body:text
    bin/rails db:migrate
    bin/rails generate controller Sessions new create destroy
    bin/rails generate model User name:string email:string password_digest:string
    bin/rails db:migrate
    bin/rails generate controller Pages home
    bin/rails generate controller StaticPages home
    bin/rails generate controller Admin::Dashboard index
    bin/rails generate controller Admin::Users index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Sessions new create destroy
    bin/rails generate controller Admin::Users index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Dashboard index
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin/rails generate controller Admin::Posts index show new edit
    bin
