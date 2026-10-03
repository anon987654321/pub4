// Reflects installed-PWA state onto the document so CSS and the install prompt
// can tell an installed launch from a browser tab.
//
// amber and bsdports both carried data-controller="pwa-standalone" with a
// data-pwa-key beside it and nothing implemented either one: the identifier
// resolved to no controller and the key had no reader anywhere in the tree. The
// two things they were for are real, so this does them rather than dropping the
// attributes.
//
//   [data-pwa-display="standalone"] — a CSS hook (see _shell_widgets.scss: the
//   install prompt is pointless once installed, and the home indicator needs
//   safe-area padding the browser chrome used to supply).
//
//   data-pwa-key — namespaces the install-prompt dismissal so a host serving
//   more than one app surface cannot have one app's dismissal silence another's.
//   install_prompt_controller.js reads the same key via dismissalKey().
import { Controller } from "@hotwired/stimulus"

const QUERIES = ["(display-mode: standalone)", "(display-mode: minimal-ui)", "(display-mode: fullscreen)"]

export function pwaKey() {
  return document.body?.dataset?.pwaKey || "app"
}

export function installDismissedKey() {
  return `install-prompt-dismissed:${pwaKey()}`
}

export function standalone() {
  // iOS Safari predates display-mode and only exposes navigator.standalone.
  if (window.navigator.standalone === true) return true

  return QUERIES.some(query => window.matchMedia?.(query)?.matches)
}

export default class extends Controller {
  connect() {
    this.onChange = () => this.reflect()
    this.watchers = QUERIES.map(query => window.matchMedia?.(query)).filter(Boolean)
    this.watchers.forEach(mq => mq.addEventListener?.("change", this.onChange))
    this.reflect()
  }

  disconnect() {
    this.watchers?.forEach(mq => mq.removeEventListener?.("change", this.onChange))
  }

  reflect() {
    const installed = standalone()
    document.documentElement.dataset.pwaDisplay = installed ? "standalone" : "browser"
    this.element.classList.toggle("pwa-standalone", installed)

    // Already installed — never ask again on this origin.
    if (installed) {
      try { localStorage.setItem(installDismissedKey(), "1") } catch (_) { /* private mode */ }
    }

    window.dispatchEvent(new CustomEvent("pub4:pwa-display", { detail: { key: pwaKey(), standalone: installed } }))
  }
}
