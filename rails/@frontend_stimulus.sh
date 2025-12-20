#!/usr/bin/env zsh
set -euo pipefail

# Stimulus Controllers for Rails 8 - Modern patterns with stimulus-components and stimulus-use
# Consolidates official components via importmap, keeps only 3 custom controllers

setup_stimulus_components() {
  log "Setting up official Stimulus components via importmap"
  
  # Pin official stimulus-components packages
  local components=(
    "clipboard"
    "dropdown"
    "dialog"
    "reveal"
    "character-counter"
    "password-visibility"
    "auto-submit"
    "sortable"
  )
  
  # Read importmap file once for efficiency
  local importmap_content=""
  [[ -f config/importmap.rb ]] && importmap_content=$(<config/importmap.rb)
  
  for component in "${components[@]}"; do
    if [[ "$importmap_content" != *"@stimulus-components/${component}"* ]]; then
      log "Pinning @stimulus-components/${component}"
      bin/importmap pin "@stimulus-components/${component}"
    fi
  done
  
  # Pin stimulus-use for composable behaviors
  if [[ "$importmap_content" != *"stimulus-use"* ]]; then
    log "Pinning stimulus-use"
    bin/importmap pin "stimulus-use"
  fi
  
  log "✓ Official Stimulus components pinned"
}

generate_controllers_index() {
  log "Generating controllers index with official components + custom controllers"
  mkdir -p app/javascript/controllers
  
  cat <<'EOF' > app/javascript/controllers/index.js
// Import and register all Stimulus controllers from stimulus-components and custom

import { application } from "./application"

// Official stimulus-components - registered via importmap
import Clipboard from "@stimulus-components/clipboard"
import Dropdown from "@stimulus-components/dropdown"
import Dialog from "@stimulus-components/dialog"
import Reveal from "@stimulus-components/reveal"
import CharacterCounter from "@stimulus-components/character-counter"
import PasswordVisibility from "@stimulus-components/password-visibility"
import AutoSubmit from "@stimulus-components/auto-submit"
import Sortable from "@stimulus-components/sortable"

application.register("clipboard", Clipboard)
application.register("dropdown", Dropdown)
application.register("dialog", Dialog)
application.register("reveal", Reveal)
application.register("character-counter", CharacterCounter)
application.register("password-visibility", PasswordVisibility)
application.register("auto-submit", AutoSubmit)
application.register("sortable", Sortable)

// Custom controllers - kept for specific app needs
import InfiniteScrollController from "./infinite_scroll_controller"
import SearchController from "./search_controller"
import NotificationController from "./notification_controller"

application.register("infinite-scroll", InfiniteScrollController)
application.register("search", SearchController)
application.register("notification", NotificationController)
EOF
  
  log "✓ controllers index with official + custom controllers"
}

generate_infinite_scroll_controller() {
  log "Generating infinite-scroll controller with stimulus-use"
  mkdir -p app/javascript/controllers
  
  cat <<'EOF' > app/javascript/controllers/infinite_scroll_controller.js
import { Controller } from "@hotwired/stimulus"
import { useIntersection } from "stimulus-use"

export default class extends Controller {
  static values = {
    url: String,
    page: { type: Number, default: 1 }
  }

  connect() {
    useIntersection(this)
  }

  appear(entry) {
    if (this.loading) return
    this.loadMore()
  }

  async loadMore() {
    this.loading = true
    const nextPage = this.pageValue + 1
    
    try {
      const response = await fetch(`${this.urlValue}?page=${nextPage}`, {
        headers: { "Accept": "text/html" }
      })
      
      if (response.ok) {
        const html = await response.text()
        this.element.insertAdjacentHTML("beforebegin", html)
        this.pageValue = nextPage
      }
    } catch (error) {
      console.error("Failed to load more:", error)
    } finally {
      this.loading = false
    }
  }
}
EOF
  
  log "✓ infinite-scroll controller with useIntersection"
}

generate_search_controller() {
  log "Generating search controller with stimulus-use debounce"
  mkdir -p app/javascript/controllers
  
  cat <<'EOF' > app/javascript/controllers/search_controller.js
import { Controller } from "@hotwired/stimulus"
import { useDebounce } from "stimulus-use"

export default class extends Controller {
  static targets = ["input", "results"]

  connect() {
    useDebounce(this, { wait: 300 })
  }

  search() {
    const query = this.inputTarget.value.trim()
    
    if (query.length < 2) {
      this.resultsTarget.innerHTML = ""
      return
    }
    
    this.performSearch(query)
  }

  async performSearch(query) {
    try {
      const response = await fetch(`/search?q=${encodeURIComponent(query)}`, {
        headers: { "Accept": "text/html" }
      })
      
      if (response.ok) {
        this.resultsTarget.innerHTML = await response.text()
      }
    } catch (error) {
      console.error("Search failed:", error)
    }
  }
}
EOF
  
  log "✓ search controller with useDebounce"
}

generate_notification_controller() {
  log "Generating notification controller"
  mkdir -p app/javascript/controllers
  
  cat <<'EOF' > app/javascript/controllers/notification_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    duration: { type: Number, default: 5000 }
  }

  connect() {
    this.timeout = setTimeout(() => this.dismiss(), this.durationValue)
  }

  dismiss() {
    this.element.remove()
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
EOF
  
  log "✓ notification controller"
}

setup_all_stimulus() {
  log "Setting up all Stimulus components and controllers"
  setup_stimulus_components
  generate_controllers_index
  generate_infinite_scroll_controller
  generate_search_controller
  generate_notification_controller
  log "✓ All Stimulus setup complete - using official components + 3 custom controllers"
}
