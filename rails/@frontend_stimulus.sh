#!/usr/bin/env zsh
set -euo pipefail

# Stimulus Controllers for Rails 8
# Per master.yml v101.0: Use stimulus-components.com before custom code

setup_stimulus_components() {
  log "Installing stimulus-components via importmap"
  bin/importmap pin @stimulus-components/clipboard
  bin/importmap pin @stimulus-components/dropdown
  bin/importmap pin @stimulus-components/dialog
  bin/importmap pin @stimulus-components/reveal
  bin/importmap pin @stimulus-components/character-counter
  bin/importmap pin @stimulus-components/password-visibility
  bin/importmap pin @stimulus-components/auto-submit
  bin/importmap pin stimulus-use
  log "Stimulus components installed"
}

generate_mapbox_controller() {
  log "Generating mapbox controller"
  mkdir -p app/javascript/controllers
  
  cat <<'EOF' > app/javascript/controllers/mapbox_controller.js
import { Controller } from "@hotwired/stimulus"
import mapboxgl from "mapbox-gl"

export default class extends Controller {
  static values = {
    accessToken: String,
    center: { type: Array, default: [0, 0] },
    zoom: { type: Number, default: 9 }
  }

  connect() {
    mapboxgl.accessToken = this.accessTokenValue
    this.map = new mapboxgl.Map({
      container: this.element,
      style: "mapbox://styles/mapbox/streets-v11",
      center: this.centerValue,
      zoom: this.zoomValue
    })
  }

  disconnect() {
    this.map.remove()
  }
}
EOF
  log "mapbox controller generated"
}

generate_search_controller() {
  log "Generating search controller (with stimulus-use)"
  mkdir -p app/javascript/controllers
  
  cat <<'EOF' > app/javascript/controllers/search_controller.js
import { Controller } from "@hotwired/stimulus"
import { useDebounce } from "stimulus-use"

export default class extends Controller {
  static targets = ["input", "results"]
  static debounces = ["search"]

  connect() {
    useDebounce(this, { wait: 300 })
  }

  search() {
    const query = this.inputTarget.value
    if (query.length < 2) return

    fetch(`/search?q=${encodeURIComponent(query)}`, {
      headers: { "Accept": "text/vnd.turbo-stream.html" }
    })
    .then(response => response.text())
    .then(html => {
      this.resultsTarget.innerHTML = html
    })
  }
}
EOF
  log "search controller generated"
}

generate_infinite_scroll_controller() {
  log "Generating infinite-scroll controller (with stimulus-use)"
  mkdir -p app/javascript/controllers
  
  cat <<'EOF' > app/javascript/controllers/infinite_scroll_controller.js
import { Controller } from "@hotwired/stimulus"
import { useIntersection } from "stimulus-use"

export default class extends Controller {
  static values = { url: String }

  connect() {
    useIntersection(this)
  }

  appear(entry) {
    if (this.hasUrlValue) {
      fetch(this.urlValue, {
        headers: { "Accept": "text/vnd.turbo-stream.html" }
      })
      .then(response => response.text())
      .then(html => Turbo.renderStreamMessage(html))
    }
  }
}
EOF
  log "infinite-scroll controller generated"
}

generate_all_stimulus_controllers() {
  log "Setting up Stimulus with components and custom controllers"
  setup_stimulus_components
  generate_mapbox_controller
  generate_search_controller
  generate_infinite_scroll_controller
  log "Stimulus setup complete"
}
