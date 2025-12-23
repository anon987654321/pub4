#!/usr/bin/env zsh
set -euo pipefail
# Stimulus controllers: ApplicationController base + common patterns
# stimulus-components.com integration
generate_application_controller() {
  log "Generating Stimulus ApplicationController with StimulusReflex"
  mkdir -p app/javascript/controllers
  cat <<'JS' > app/javascript/controllers/application_controller.js
import { Controller } from "@hotwired/stimulus"
import StimulusReflex from "stimulus_reflex"
// Base controller for all Stimulus controllers
// Inherit from this to get StimulusReflex + lifecycle hooks
export default class extends Controller {
  connect() {
    StimulusReflex.register(this)
    this.element.dataset.reflexId = this.reflexId
  }
  // Spinner during Reflex operations
  beforeReflex(element, reflex, noop, reflexId) {
    document.body.classList.add("wait")
    element.classList.add("loading")
  }
  reflexSuccess(element, reflex, noop, reflexId) {
    element.classList.remove("loading")
    this.handleAutofocus()
  }
  reflexError(element, reflex, error, reflexId) {
    console.error("Reflex error:", error)
    element.classList.remove("loading")
  }
  afterReflex(element, reflex, noop, reflexId) {
    document.body.classList.remove("wait")
  }
  // Autofocus pattern: browsers only autofocus on page load
  // This handles focus after Turbo/Reflex updates
  handleAutofocus() {
    const el = this.element.querySelector("[autofocus]")
    if (el) {
      el.focus()
      // Move cursor to end for inputs
      if (el.value) {
        const val = el.value
        el.value = ""
        el.value = val
      }
    }
  }
  // Helper: Dispatch custom event
  dispatch(name, detail = {}) {
    this.element.dispatchEvent(
      new CustomEvent(name, {
        detail,
        bubbles: true,
        cancelable: true
      })
    )
  }
}
JS
  log "✓ ApplicationController generated"
}
generate_infinite_scroll_controller() {
  log "Generating infinite scroll controller"
  cat <<'JS' > app/javascript/controllers/infinite_scroll_controller.js
import ApplicationController from "./application_controller"
// Infinite scroll with IntersectionObserver
// Usage: data-controller="infinite-scroll" data-infinite-scroll-next-page-value="2"
export default class extends ApplicationController {
  static values = {
    nextPage: String,
    loading: { type: Boolean, default: false }
  }
  static targets = ["trigger"]
  connect() {
    super.connect()
    this.observer = new IntersectionObserver(
      entries => this.handleIntersect(entries),
      { threshold: 1.0 }
    )
    if (this.hasTriggerTarget) {
      this.observer.observe(this.triggerTarget)
    }
  }
  disconnect() {
    this.observer?.disconnect()
  }
  handleIntersect(entries) {
    entries.forEach(entry => {
      if (entry.isIntersecting && !this.loadingValue && this.nextPageValue) {
        this.loadMore()
      }
    })
  }
  async loadMore() {
    this.loadingValue = true
    try {
      const response = await fetch(this.nextPageValue, {
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          "Turbo-Frame": this.element.id
        }
      })
      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
      }
    } catch (error) {
      console.error("Infinite scroll error:", error)
    } finally {
      this.loadingValue = false
    }
  }
}
JS
  log "✓ Infinite scroll controller generated"
}
generate_modal_controller() {
  log "Generating modal controller"
  cat <<'JS' > app/javascript/controllers/modal_controller.js
import ApplicationController from "./application_controller"
// Modal for Turbo Frames
// Usage: data-controller="modal" on turbo-frame#modal
export default class extends ApplicationController {
  connect() {
    super.connect()
    this.element.addEventListener("turbo:frame-load", this.open.bind(this))
    this.element.addEventListener("turbo:submit-end", this.handleSubmit.bind(this))
  }
  open() {
    const dialog = this.element.querySelector("dialog")
    dialog?.showModal()
    // Close on backdrop click
    dialog?.addEventListener("click", (e) => {
      if (e.target === dialog) {
        this.close()
      }
    })
    // Close on Escape key
    dialog?.addEventListener("cancel", () => this.close())
  }
  handleSubmit(event) {
    if (event.detail.success) {
      this.close()
    }
  }
  close() {
    const dialog = this.element.querySelector("dialog")
    dialog?.close()
    this.element.innerHTML = ""
  }
}
JS
  log "✓ Modal controller generated"
}
generate_form_validation_controller() {
  log "Generating form validation controller"
  cat <<'JS' > app/javascript/controllers/form_validation_controller.js
import ApplicationController from "./application_controller"
// Form validation and submit button state
// Usage: data-controller="form-validation"
export default class extends ApplicationController {
  static targets = ["submit"]
  connect() {
    super.connect()
    this.element.addEventListener("turbo:submit-start", () => this.disable())
    this.element.addEventListener("turbo:submit-end", () => this.enable())
  }
  disable() {
    this.submitTargets.forEach(btn => {
      btn.disabled = true
      btn.dataset.originalText = btn.textContent
      btn.textContent = btn.dataset.loadingText || "Saving..."
    })
  }
  enable() {
    this.submitTargets.forEach(btn => {
      btn.disabled = false
      btn.textContent = btn.dataset.originalText || "Save"
    })
  }
}
JS
  log "✓ Form validation controller generated"
}
generate_reveal_controller() {
  log "Generating reveal controller for flash messages"
  cat <<'JS' > app/javascript/controllers/reveal_controller.js
import { useTransition } from "stimulus-use"
import ApplicationController from "./application_controller"
// Animated reveal/hide for flash messages
// Usage: data-controller="reveal"
export default class extends ApplicationController {
  static values = {
    hiddenClass: { type: String, default: "hidden" },
    visibleClass: { type: String, default: "show" },
    removeDelay: { type: Number, default: 5000 }
  }
  connect() {
    super.connect()
    useTransition(this, { element: this.element })
    this.show()
    this.timeout = setTimeout(() => this.hide(), this.removeDelayValue)
  }
  disconnect() {
    clearTimeout(this.timeout)
  }
  show() {
    this.enter()
  }
  hide() {
    this.leave()
  }
  remove() {
    this.element.remove()
  }
}
JS
  log "✓ Reveal controller generated"
}
# Install stimulus-components from stimulus-components.com
install_stimulus_components() {
  log "Installing stimulus-components.com packages"
  local -a components=(
    "@stimulus-components/auto-submit"
    "@stimulus-components/character-counter"
    "@stimulus-components/checkbox-select-all"
    "@stimulus-components/clipboard"
    "@stimulus-components/dialog"
    "@stimulus-components/dropdown"
    "@stimulus-components/password-visibility"
    "@stimulus-components/reveal"
    "@stimulus-components/sortable"
    "@stimulus-components/timeago"
  )
  for component in "${components[@]}"; do
    install_yarn_package "$component"
  done
  # Register components in index.js
  cat <<'JS' > app/javascript/controllers/index.js
// Auto-generated by @frontend_stimulus_controllers.sh
import { application } from "./application"
// Import stimulus-components
import AutoSubmit from "@stimulus-components/auto-submit"
import CharacterCounter from "@stimulus-components/character-counter"
import CheckboxSelectAll from "@stimulus-components/checkbox-select-all"
import Clipboard from "@stimulus-components/clipboard"
import Dialog from "@stimulus-components/dialog"
import Dropdown from "@stimulus-components/dropdown"
import PasswordVisibility from "@stimulus-components/password-visibility"
import Reveal from "@stimulus-components/reveal"
import Sortable from "@stimulus-components/sortable"
import Timeago from "@stimulus-components/timeago"
// Register components
application.register("auto-submit", AutoSubmit)
application.register("character-counter", CharacterCounter)
application.register("checkbox-select-all", CheckboxSelectAll)
application.register("clipboard", Clipboard)
application.register("dialog", Dialog)
application.register("dropdown", Dropdown)
application.register("password-visibility", PasswordVisibility)
application.register("reveal", Reveal)
application.register("sortable", Sortable)
application.register("timeago", Timeago)
// Import custom controllers
import InfiniteScrollController from "./infinite_scroll_controller"
import ModalController from "./modal_controller"
import FormValidationController from "./form_validation_controller"
application.register("infinite-scroll", InfiniteScrollController)
application.register("modal", ModalController)
application.register("form-validation", FormValidationController)
JS
  log "✓ stimulus-components installed and registered"
}
setup_stimulus_controllers() {
  generate_application_controller
  generate_infinite_scroll_controller
  generate_modal_controller
  generate_form_validation_controller
  generate_reveal_controller
  install_stimulus_components
  log "✓ Complete Stimulus setup with stimulus-components.com"
}
