import { Controller } from "@hotwired/stimulus"

// Battery + visibility awareness for both brgen and amber.
//
// Usage (recommended on <body>):
//   <body data-controller="battery-aware network-aware ...">
//
// Classes toggled on <html>:
//   .battery-low       → level < threshold and not charging
//   .battery-charging  → currently charging
//   .page-hidden       → document.hidden === true
//
// Events:
//   pub4:battery-change    { detail: { level, charging, low, supported } }
//   pub4:visibility-change { detail: { hidden } }
//
export default class extends Controller {
  static values = {
    lowThreshold: { type: Number, default: 0.2 }
  }

  #battery = null
  #supported = false
  #disconnected = false

  connect() {
    this.#disconnected = false
    this.#onVisibility = this.#onVisibility.bind(this)
    document.addEventListener("visibilitychange", this.#onVisibility)

    this.#applyVisibility()

    if ("getBattery" in navigator) {
      navigator.getBattery()
        .then(battery => {
          if (this.#disconnected) return
          this.#battery = battery
          this.#supported = true
          this.#applyBattery()

          battery.addEventListener("levelchange", this.#onBatteryChange)
          battery.addEventListener("chargingchange", this.#onBatteryChange)
        })
        .catch(() => {
          this.#supported = false
        })
    }
  }

  disconnect() {
    this.#disconnected = true
    document.removeEventListener("visibilitychange", this.#onVisibility)

    if (this.#battery) {
      this.#battery.removeEventListener("levelchange", this.#onBatteryChange)
      this.#battery.removeEventListener("chargingchange", this.#onBatteryChange)
      this.#battery = null
    }
  }

  #onVisibility() {
    this.#applyVisibility()
  }

  #onBatteryChange = () => {
    this.#applyBattery()
  }

  #applyVisibility() {
    const hidden = document.hidden
    document.documentElement.classList.toggle("page-hidden", hidden)

    window.dispatchEvent(new CustomEvent("pub4:visibility-change", {
      detail: { hidden }
    }))
  }

  #applyBattery() {
    if (!this.#battery) return

    const level = this.#battery.level
    const charging = this.#battery.charging
    const low = level < this.lowThresholdValue && !charging

    document.documentElement.classList.toggle("battery-low", low)
    document.documentElement.classList.toggle("battery-charging", charging)

    window.dispatchEvent(new CustomEvent("pub4:battery-change", {
      detail: {
        level,
        charging,
        low,
        supported: this.#supported
      }
    }))
  }
}
