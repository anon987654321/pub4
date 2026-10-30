import { Controller } from "@hotwired/stimulus"

// Adapts the UI to current network *and* battery conditions.
//
// Recommended on <body>:
//   <body data-controller="battery-aware network-aware ...">
//
// Classes:
//   .network-slow
//   .network-save-data
//   .network-offline
//   .power-constrained
//
// An `offline` target (shared/_offline_status) is shown while the browser
// reports no connection, and hidden again when it comes back.
export default class extends Controller {
  static targets = ["heavy", "offline"]

  #batteryLow = false
  #connection = null

  connect() {
    this.#connection = navigator.connection || navigator.mozConnection || navigator.webkitConnection

    window.addEventListener("pub4:battery-change", this.#onBatteryChange)
    window.addEventListener("online", this.#apply)
    window.addEventListener("offline", this.#apply)

    if (this.#connection) {
      this.#connection.addEventListener("change", this.#apply)
    }

    this.#apply()
  }

  disconnect() {
    window.removeEventListener("pub4:battery-change", this.#onBatteryChange)
    window.removeEventListener("online", this.#apply)
    window.removeEventListener("offline", this.#apply)
    this.#connection?.removeEventListener("change", this.#apply)
  }

  #onBatteryChange = (event) => {
    this.#batteryLow = !!event.detail?.low
    this.#apply()
  }

  #apply = () => {
    const c = this.#connection
    let slow = false
    let saveData = false

    if (c) {
      saveData = !!c.saveData
      slow = saveData || ["slow-2g", "2g", "3g"].includes(c.effectiveType)
    }

    // Combined low battery + slow network (the patch's || form collapsed to
    // battery-only; AND is what .power-constrained's comment describes).
    const powerConstrained = this.#batteryLow && slow
    const offline = navigator.onLine === false

    document.documentElement.classList.toggle("network-offline", offline)
    this.offlineTargets.forEach(el => { el.hidden = !offline })
    document.documentElement.classList.toggle("network-slow", !!slow)
    document.documentElement.classList.toggle("network-save-data", saveData)
    document.documentElement.classList.toggle("power-constrained", powerConstrained)

    this.heavyTargets.forEach(el => {
      if (el.tagName === "VIDEO" || el.tagName === "AUDIO") {
        if (slow || this.#batteryLow) {
          el.removeAttribute("autoplay")
          el.preload = "none"
          if (this.#batteryLow && !el.paused) {
            try { el.pause() } catch (_) { /* ignore */ }
          }
        }
      }
    })

    window.dispatchEvent(new CustomEvent("pub4:network-change", {
      detail: {
        offline,
        slow: !!slow,
        saveData,
        batteryLow: this.#batteryLow,
        powerConstrained,
        effectiveType: c?.effectiveType,
        downlink: c?.downlink
      }
    }))
  }
}
