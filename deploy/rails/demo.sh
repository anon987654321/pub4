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
    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
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

    # Generate Post scaffold with Hotwire
    rails generate scaffold Post title:string content:text

    # Install Stimulus
    bin/rails stimulus:install

    # Generate modal controller
    cat > app/javascript/controllers/modal_controller.js <<EOF
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal"]

  connect() {
    document.addEventListener("turbo:before-render", this.beforeRender.bind(this))
  }

  disconnect() {
    document.removeEventListener("turbo:before-render", this.beforeRender.bind(this))
  }

  beforeRender(event) {
    if (this.modalTarget) {
      this.modalTarget.showModal()
    }
  }

  show() {
    this.modalTarget.showModal()
  }

  hide() {
    this.modalTarget.close()
  }
}
EOF

    # Update posts index view with modal
    cat > app/views/posts/index.html.erb <<EOF
<div data    <div id="post_modal_content"></div>
    <button data-action="modal#hide">Close</button>
  </dialog>

  <h1>Posts</h1>

  <div id="posts">
    <%= render @posts %>
  </div>

  <%= link_to "New post", new_post_path,
              data: { turbo_frame: "post_modal_content" },
              class: "rounded-lg-block font-medium cursor-pointer" %>
</div>
EOF

    # Update.html.erb <<EOF
<div id="<%= dom_id post %>"my-5">
    <strong class="block font-medium mb-1 <p class="my-5">
    <strong class="block font  </p>

  <div class="flex space-x-2">
 %>
    <%= link_to "Edit", edit_post_path(post),
                class: "rounded-lg py-2 px-4 bg-gray-100 inline-block font-medium" %>
    <%= button_to "Delete", post, method: :delete,
                  class: "rounded-lg py-2 px-4 bg-red-100 text-red-700 inline-block font-medium cursor-pointer",
                  form: { data: { turbo_confirm: "Are you sure?" } } %>
  </div>
</div>
EOF

    # Run migrations
    bin/rails db:migrate

    echo "App generated successfully!"
    echo "Run: cd $APP_NAME && bin/dev"
    echo "Visit: http://localhost:$PORT"
}

main "$@"
```
