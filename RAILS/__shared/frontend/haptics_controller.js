import { Controller } from "@hotwired/stimulus"

// Lightweight haptic feedback for both brgen and amber.
// Automatically suppressed when battery is low or page is hidden.
//
// Usage:
//   <button data-controller="haptics" data-action="click->haptics#tick">Like</button>
//   <button data-controller="haptics" data-action="click->haptics#success">Save</button>
//   <button data-controller="haptics" data-action="click->haptics#match">Match</button>
//
export default class extends Controller {
  static values = {
    pattern: String
  }

  tick() {
    if (this.#shouldSuppress()) return
    this.#vibrate(12)
  }

  success() {
    if (this.#shouldSuppress()) return
    this.#vibrate([12, 40, 18])
  }

  match() {
    if (this.#shouldSuppress()) return
    this.#vibrate([18, 30, 18, 30, 40])
  }

  warning() {
    if (this.#shouldSuppress()) return
    this.#vibrate([30, 50, 30])
  }

  play() {
    if (this.#shouldSuppress()) return
    const map = {
      light: 10,
      medium: 20,
      heavy: 35,
      success: [12, 40, 18],
      warning: [30, 50, 30],
      error: [40, 30, 40, 30, 60]
    }
    this.#vibrate(map[this.patternValue] || 15)
  }

  #shouldSuppress() {
    return document.hidden ||
           document.documentElement.classList.contains("battery-low") ||
           document.documentElement.classList.contains("page-hidden")
  }

  #vibrate(pattern) {
    if (!navigator.vibrate) return
    try {
      navigator.vibrate(pattern)
    } catch (_) { /* ignore */ }
  }
}
