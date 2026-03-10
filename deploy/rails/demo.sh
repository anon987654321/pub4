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

    # Create new Rails app
    if ! rails new "$APP_NAME" \
        --database=postgresql \
        --css=tailwind \
        --javascript=importmap; then
        echo "Error: Failed to create Rails app" >&2
        exit 1
    fi

    cd "$APP_NAME" || { echo "Error: Failed to enter app directory" >&2; exit 1; }

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
    if ! bin/rails db:create; then
        echo "Error: Failed to create databases" >&2
        exit 1
    fi

    # Add Solid Queue, Cache, Cable
    if ! bundle add solid_queue solid_cache solid_cable; then
        echo "Error: Failed to add Solid* gems" >&2
        exit 1
    fi

    # Backup existing application.rb if present
    if [[ -f config/application.rb ]]; then
        cp -f config/application.rb config/application.rb.backup
    fi

    # Configure for production
    if [[ -f config/application.rb ]] && ! grep -q "config.active_job.queue_adapter" config/application.rb; then
        cat >> config/application.rb <<EOF

    # Solid* stack
    config.active_job.queue_adapter = :solid_queue
    config.cache_store = :solid_cache_store
    config.action_cable.adapter = :solid_cable
EOF
    fi

    echo "Application created successfully. Remember to set ${APP_NAME^^}_DATABASE_PASSWORD environment variable for production."
}

main "$@"
```
