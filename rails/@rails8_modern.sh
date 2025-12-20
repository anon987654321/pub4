#!/usr/bin/env zsh
set -euo pipefail

# Rails 8 Modern Stack Setup
# - Built-in authentication
# - StimulusReflex v3.5+
# - stimulus-components (from stimulus-components.com)
# - Clean HTML (no div/section-itis)

setup_rails8_authentication() {
  log "Setting up Rails 8 built-in authentication"
  
  # Rails 8 has authentication generator
  if [[ ! -f "app/models/session.rb" ]]; then
    bin/rails generate authentication
    log "✓ Rails 8 authentication generated"
  else
    log "Authentication already configured"
  fi
}

install_stimulus_components() {
  log "Installing stimulus-components from stimulus-components.com"
  
  # Core components for common UI patterns (zsh array)
  local -a components
  components=(
    "@stimulus-components/clipboard"
    "@stimulus-components/dropdown"
    "@stimulus-components/dialog"
    "@stimulus-components/character-counter"
    "@stimulus-components/password-visibility"
    "@stimulus-components/checkbox-select-all"
    "@stimulus-components/sortable"
    "@stimulus-components/reveal"
    "@stimulus-components/auto-submit"
  )
  
  for component in "${components[@]}"; do
    # install_yarn_package is defined in @helpers.sh which is sourced by @shared_functions.sh
    if command -v install_yarn_package >/dev/null 2>&1; then
      install_yarn_package "$component"
    else
      log "Installing $component via yarn"
      yarn add "$component"
    fi
  done
  
  log "✓ Stimulus components installed"
}

setup_stimulus_reflex_modern() {
  log "Setting up StimulusReflex v3.5+ for Rails 8"
  
  install_gem "stimulus_reflex"
  install_yarn_package "stimulus_reflex"
  
  # Rails 8 uses Solid Cable by default, but StimulusReflex works with it
  if [[ ! -f "config/initializers/stimulus_reflex.rb" ]]; then
    bin/rails generate stimulus_reflex:install
    log "✓ StimulusReflex configured for Rails 8"
  fi
  
  # Enable caching for development (required for StimulusReflex)
  if [[ ! -f "tmp/caching-dev.txt" ]]; then
    bin/rails dev:cache
  fi
}

generate_clean_layout() {
  local app_name="${1:-App}"
  
  log "Generating clean HTML layout (no divitis)"
  
  cat <<EOF > app/views/layouts/application.html.erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title><%= content_for?(:title) ? yield(:title) + " - ${app_name}" : "${app_name}" %></title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>
</head>
<body>
  <% if current_user %>
    <nav>
      <%= link_to "Home", root_path %>
      <%= button_to "Sign out", session_path, method: :delete %>
    </nav>
  <% end %>
  
  <% if flash.any? %>
    <% flash.each do |type, msg| %>
      <output data-controller="reveal" data-reveal-hidden-class="hidden"><%= msg %></output>
    <% end %>
  <% end %>
  
  <main>
    <%= yield %>
  </main>
</body>
</html>
EOF
  
  log "✓ Clean semantic HTML layout generated"
}

generate_stimulus_components_examples() {
  log "Generating example controllers for stimulus-components"
  
  mkdir -p app/javascript/controllers
  
  # Register stimulus-components in application
  cat <<'EOF' > app/javascript/controllers/application.js
import { Application } from "@hotwired/stimulus"
import { StimulusReflex } from "stimulus_reflex"

const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus = application

// Initialize StimulusReflex after application is configured
StimulusReflex.initialize(application)

export { application }
EOF

  # Create example using clipboard component
  cat <<'EOF' > app/javascript/controllers/clipboard_controller.js
import Clipboard from "@stimulus-components/clipboard"

export default class extends Clipboard {
  connect() {
    super.connect()
    console.log("Clipboard controller connected")
  }
  
  copied() {
    // Override to customize behavior after copy
    this.element.classList.add("copied")
    setTimeout(() => this.element.classList.remove("copied"), 2000)
  }
}
EOF

  # Create example using dropdown component
  cat <<'EOF' > app/javascript/controllers/dropdown_controller.js
import Dropdown from "@stimulus-components/dropdown"

export default class extends Dropdown {
  connect() {
    super.connect()
  }
}
EOF

  # Create example using sortable component
  cat <<'EOF' > app/javascript/controllers/sortable_controller.js
import Sortable from "@stimulus-components/sortable"

export default class extends Sortable {
  connect() {
    super.connect()
  }
  
  // Called when sort order changes
  end(event) {
    const order = [...this.element.children].map(el => el.dataset.id)
    // Send to server via Turbo or fetch
    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
      },
      body: JSON.stringify({ order })
    })
  }
}
EOF

  log "✓ Stimulus components examples generated"
}

setup_modern_rails8_stack() {
  log "Setting up complete Rails 8 modern stack"
  
  setup_rails8_authentication
  install_stimulus_components
  setup_stimulus_reflex_modern
  generate_stimulus_components_examples
  
  log "✓ Rails 8 modern stack complete: authentication, StimulusReflex, stimulus-components"
}
