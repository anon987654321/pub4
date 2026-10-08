// Nav roving-tabindex + standalone-PWA chrome, as a real Stimulus controller
// instead of a global script wired to DOMContentLoaded/turbo:load with manual
// init-once flags -- lifecycle follows connect()/disconnect() like every other
// controller in this app.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["navSections"]

  connect() {
    this.onNavKeydown = this.onNavKeydown.bind(this)

    if (this.hasNavSectionsTarget) {
      this.navSectionsTarget.addEventListener("keydown", this.onNavKeydown)
    }

    this.syncStandaloneMode()
  }

  disconnect() {
    if (this.hasNavSectionsTarget) {
      this.navSectionsTarget.removeEventListener("keydown", this.onNavKeydown)
    }
  }

  // Selects .nav_link, not [role="tab"]: _nav_swiper dropped the tablist roles
  // because those entries are links that navigate and there is no tabpanel to
  // control. Arrow keys still walk the bar, but tabIndex is left alone -- a
  // tablist is deliberately one tab stop, whereas every link in a nav should
  // stay reachable by Tab.
  onNavKeydown(e) {
    const tabs = Array.from(this.navSectionsTarget.querySelectorAll(".nav_link"))
    const i = tabs.indexOf(document.activeElement)
    if (i < 0) return
    let next = i
    if (e.key === "ArrowRight" || e.key === "ArrowDown") next = (i + 1) % tabs.length
    else if (e.key === "ArrowLeft" || e.key === "ArrowUp") next = (i - 1 + tabs.length) % tabs.length
    else if (e.key === "Home") next = 0
    else if (e.key === "End") next = tabs.length - 1
    else return
    e.preventDefault()
    tabs[next].focus()
  }

  syncStandaloneMode() {
    const standalone = window.matchMedia("(display-mode: standalone)").matches
    const mode = standalone ? "standalone" : "browser"
    // Conditional because <html> is the root Stimulus observes, and re-setting
    // an attribute to its current value still queues a mutation record --
    // nearby_chat_controller turned exactly that into an unbreakable
    // MutationObserver loop (see the note on #setTab there).
    if (document.documentElement.dataset.displayMode !== mode) {
      document.documentElement.dataset.displayMode = mode
    }
    document.querySelectorAll("nav").forEach((nav) => nav.classList.toggle("nav-visible", standalone))
  }
}
