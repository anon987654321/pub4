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

    # Add Solid Queue, Cache, Cable with error handling
    if ! bundle add solid_queue solid_cache solid_cable; then
        echo "Error: Failed to add Solid* gems" >&2
        exit 1
    fi

    # Configure Solid* gems in application.rb without hardcoded Redis URL
    local application_rb="config/application.rb"
    if [[ -f "$application_rb" ]]; then
        cp -f "$application_rb" "${application_rb}.backup"

        # Only add configurations if they don't already exist
        if ! grep -q "config.solid_queue" "$application_rb"; then
            cat >> "$application_rb" <<'EOF'

# Solid Queue configuration
config.solid_queue.connects_to = { database: { writing: :primary } }
EOF
        fi

        if ! grep -q "config.solid_cache" "$application_rb"; then
            cat >> "$application_rb" <<'EOF'

# Solid Cache configuration
config.solid_cache.connects_to = { database: { writing: :primary } }
EOF
        fi

        if ! grep -q "config.solid_cable" "$application_rb"; then
            cat >> "$application_rb" <<'EOF'

# Solid Cable configuration
config.solid_cable.connects_to = { database: { writing: :primary } }
EOF
        fi
    fi

    # Generate scaffold for demo resource
    bin/rails generate scaffold Post title:string content:text --no-jbuilder

    # Run migrations
    if ! bin/rails db:migrate; then
        echo "Error: Failed to run migrations" >&2
        exit 1
    fi

    # Update routes
    echo "Rails.application.routes.draw do
  resources :posts
  root 'posts#index'
end" > config/routes.rb

    # Add basic styling to application layout
    local layout_file="app/views/layouts/application.html.erb"
    if [[ -f "$layout_file" ]]; then
        sed -i.bak '/<body>/a\
    <div class="container mx-auto px-4 py-8">\
      <h1 class="text-3xl font-bold mb-6">Demo App</h1>\
      <%= yield %>\
    </div>' "$layout_file"
        rm -f "${layout_file}.bak"
    fi

    # Start the server in background
    bin/rails server -p $PORT -d

    echo "Demo app created successfully!"
    echo "App is running on http://localhost:$PORT"
    echo "You can stop the server with: bin/rails server -p $PORT -d -s"
}

main "$@"
```
