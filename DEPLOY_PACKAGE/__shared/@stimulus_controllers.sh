#!/usr/bin/env zsh
set -euo pipefail

# Stimulus controller generators for Rails 8 PWA
# All controllers follow master.json requirements:

# - init: constants only
# - connect: setup with cleanup

# - disconnect: ALWAYS present with full cleanup
generate_character_counter_controller() {

  log "Generating character-counter Stimulus controller"

  mkdir -p app/javascript/controllers

  cat <<'EOF' > app/javascript/controllers/character_counter_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  static targets = ["input", "count"]
  static values = { max: Number }
  connect() {

    this.update()
  }

  update() {

    const length = this.inputTarget.value.length
    this.countTarget.textContent = this.hasMaxValue

      ? `${length} / ${this.maxValue}`

      : length
  }

  disconnect() {

    // Cleanup not needed for this controller

  }

}

EOF
  log "character-counter controller generated"

}

generate_textarea_autogrow_controller() {

  log "Generating textarea-autogrow Stimulus controller"

  mkdir -p app/javascript/controllers
  cat <<'EOF' > app/javascript/controllers/textarea_autogrow_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  static targets = ["input"]
  connect() {
    this.resize()

  }
  resize() {

    this.inputTarget.style.height = "auto"
    this.inputTarget.style.height = `${this.inputTarget.scrollHeight}px`

  }

  disconnect() {
    // Cleanup not needed for this controller

  }

}

EOF
  log "textarea-autogrow controller generated"

}

generate_dropdown_controller() {

  log "Generating dropdown Stimulus controller"

  mkdir -p app/javascript/controllers
  cat <<'EOF' > app/javascript/controllers/dropdown_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  static targets = ["menu"]
  connect() {
    this.boundClickOutside = this.clickOutside.bind(this)

  }
  toggle(event) {

    event.preventDefault()
    this.menuTarget.classList.toggle("hidden")

    if (!this.menuTarget.classList.contains("hidden")) {

      document.addEventListener("click", this.boundClickOutside)
    } else {

      document.removeEventListener("click", this.boundClickOutside)

    }
  }

  clickOutside(event) {

    if (!this.element.contains(event.target)) {

      this.close()

    }

  }
  close() {

    this.menuTarget.classList.add("hidden")

    document.removeEventListener("click", this.boundClickOutside)

  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside)

  }

}

EOF
  log "dropdown controller generated"

}

generate_modal_controller() {

  log "Generating modal Stimulus controller"

  mkdir -p app/javascript/controllers
  cat <<'EOF' > app/javascript/controllers/modal_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  connect() {
    this.boundHandleKeyup = this.handleKeyup.bind(this)
    document.addEventListener("keyup", this.boundHandleKeyup)

  }
  open(event) {

    event.preventDefault()

    this.element.showModal()

  }

  close() {
    this.element.close()

  }

  handleKeyup(event) {

    if (event.key === "Escape") {
      this.close()

    }

  }
  backdropClick(event) {

    if (event.target === this.element) {

      this.close()

    }

  }
  disconnect() {

    document.removeEventListener("keyup", this.boundHandleKeyup)

  }

}

EOF
  log "modal controller generated"

}

generate_clipboard_controller() {

  log "Generating clipboard Stimulus controller"

  mkdir -p app/javascript/controllers
  cat <<'EOF' > app/javascript/controllers/clipboard_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  static targets = ["source", "button"]
  static values = { successMessage: { type: String, default: "Copied!" } }
  copy(event) {

    event.preventDefault()
    const text = this.sourceTarget.value || this.sourceTarget.textContent

    navigator.clipboard.writeText(text).then(() => {

      this.showSuccess()
    }).catch(err => {

      console.error("Failed to copy:", err)
    })

  }

  showSuccess() {

    if (!this.hasButtonTarget) return

    const originalText = this.buttonTarget.textContent

    this.buttonTarget.textContent = this.successMessageValue

    this.timeout = setTimeout(() => {
      this.buttonTarget.textContent = originalText

    }, 2000)
  }

  disconnect() {
    clearTimeout(this.timeout)

  }

}

EOF
  log "clipboard controller generated"

}

generate_autosave_controller() {

  log "Generating autosave Stimulus controller"

  mkdir -p app/javascript/controllers
  cat <<'EOF' > app/javascript/controllers/autosave_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  static values = { delay: { type: Number, default: 1000 } }
  connect() {
    this.timeout = null

  }
  save() {

    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {

      this.element.requestSubmit()

    }, this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)

  }

}

EOF
  log "autosave controller generated"

}

generate_password_visibility_controller() {

  log "Generating password-visibility Stimulus controller"

  mkdir -p app/javascript/controllers
  cat <<'EOF' > app/javascript/controllers/password_visibility_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  static targets = ["input", "icon"]
  toggle(event) {
    event.preventDefault()

    const type = this.inputTarget.type === "password" ? "text" : "password"
    this.inputTarget.type = type

    if (this.hasIconTarget) {
      this.iconTarget.textContent = type === "password" ? "👁" : "👁‍🗨"

    }
  }

  disconnect() {
    // Cleanup not needed for this controller

  }

}

EOF
  log "password-visibility controller generated"

}

generate_form_validation_controller() {

  log "Generating form-validation Stimulus controller"

  mkdir -p app/javascript/controllers
  cat <<'EOF' > app/javascript/controllers/form_validation_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  static targets = ["input", "error"]
  validate(event) {
    const input = event.target

    const errorTarget = this.errorTargets.find(
      el => el.dataset.for === input.id

    )
    if (!errorTarget) return

    if (input.validity.valid) {

      errorTarget.textContent = ""

      input.classList.remove("invalid")

    } else {
      errorTarget.textContent = input.validationMessage
      input.classList.add("invalid")

    }

  }

  disconnect() {

    // Cleanup not needed for this controller

  }

}

EOF
  log "form-validation controller generated"

}

generate_infinite_scroll_controller() {

  log "Generating infinite-scroll Stimulus controller"

  mkdir -p app/javascript/controllers
  cat <<'EOF' > app/javascript/controllers/infinite_scroll_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  connect() {
    this.observer = new IntersectionObserver(
      entries => this.handleIntersection(entries),

      { threshold: 0.1 }
    )

    const sentinel = document.getElementById("sentinel")

    if (sentinel) {

      this.observer.observe(sentinel)

    }

  }
  handleIntersection(entries) {

    entries.forEach(entry => {

      if (entry.isIntersecting) {

        this.loadMore()

      }
    })

  }

  loadMore() {

    // Trigger reflex or fetch for more content

    const sentinel = document.getElementById("sentinel")

    if (sentinel && sentinel.dataset.reflex) {

      this.stimulate(sentinel.dataset.reflex)
    }

  }

  disconnect() {

    if (this.observer) {

      this.observer.disconnect()

    }

  }
}

EOF

  log "infinite-scroll controller generated"

}

generate_search_controller() {

  log "Generating search Stimulus controller"

  mkdir -p app/javascript/controllers
  cat <<'EOF' > app/javascript/controllers/search_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  static targets = ["input", "results"]
  static values = { delay: { type: Number, default: 300 } }
  connect() {

    this.timeout = null
  }

  search() {

    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {

      const query = this.inputTarget.value.trim()

      if (query.length < 2) {
        this.resultsTarget.innerHTML = ""

        return
      }

      this.performSearch(query)
    }, this.delayValue)

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

  disconnect() {

    clearTimeout(this.timeout)

  }

}

EOF
  log "search controller generated"

}

generate_notification_controller() {

  log "Generating notification Stimulus controller"

  mkdir -p app/javascript/controllers
  cat <<'EOF' > app/javascript/controllers/notification_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  static values = { duration: { type: Number, default: 5000 } }
  connect() {
    this.timeout = setTimeout(() => {

      this.dismiss()
    }, this.durationValue)

  }
  dismiss() {

    this.element.remove()

  }

  disconnect() {

    clearTimeout(this.timeout)
  }

}

EOF
  log "notification controller generated"

}

generate_dialog_controller() {

  log "Generating dialog Stimulus controller"

  mkdir -p app/javascript/controllers
  cat <<'EOF' > app/javascript/controllers/dialog_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  connect() {
    this.boundHandleKeyup = this.handleKeyup.bind(this)
    document.addEventListener("keyup", this.boundHandleKeyup)

  }
  open(event) {

    if (event) event.preventDefault()

    this.element.showModal()

  }

  close(event) {
    if (event) event.preventDefault()

    this.element.close()

  }

  handleKeyup(event) {
    if (event.key === "Escape") {

      this.close()

    }

  }
  backdropClick(event) {

    if (event.target === this.element) {

      this.close()

    }

  }
  disconnect() {

    document.removeEventListener("keyup", this.boundHandleKeyup)

  }

}

EOF
  log "dialog controller generated"

}

generate_all_stimulus_controllers() {

  log "Generating all standard Stimulus controllers"

  generate_character_counter_controller
  generate_textarea_autogrow_controller

  generate_dropdown_controller
  generate_modal_controller

  generate_clipboard_controller
  generate_autosave_controller

  generate_password_visibility_controller

  generate_form_validation_controller

  generate_infinite_scroll_controller

  generate_search_controller

  generate_notification_controller

  generate_dialog_controller

  log "All Stimulus controllers generated successfully!"

}

