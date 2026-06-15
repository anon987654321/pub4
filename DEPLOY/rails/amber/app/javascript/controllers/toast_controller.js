import { Controller } from "@hotwired/stimulus"

// Lightweight toast notifications (donation confirmations, expiry alerts, etc.)
export default class extends Controller {
  static targets = ["container"]
  static values = {
    message: String,
    variant: { type: String, default: "info" },
    duration: { type: Number, default: 4000 }
  }

  connect() {
    if (this.messageValue) this.show(this.messageValue)
  }

  show(message, { variant = "info", duration = this.durationValue } = {}) {
    const root = this.hasContainerTarget ? this.containerTarget : this.#ensureContainer()
    const toast = document.createElement("div")
    toast.className = `toast toast--${variant}`
    toast.setAttribute("role", "status")
    toast.textContent = message
    root.appendChild(toast)

    requestAnimationFrame(() => toast.classList.add("toast--visible"))

    const dismiss = () => {
      toast.classList.remove("toast--visible")
      toast.classList.add("toast--leaving")
      toast.addEventListener("transitionend", () => toast.remove(), { once: true })
      setTimeout(() => toast.remove(), 500)
    }

    const timer = window.setTimeout(dismiss, duration)
    toast.addEventListener("click", () => {
      window.clearTimeout(timer)
      dismiss()
    })
  }

  #ensureContainer() {
    let root = document.getElementById("toast-root")
    if (!root) {
      root = document.createElement("div")
      root.id = "toast-root"
      root.className = "toast-root"
      root.setAttribute("aria-live", "polite")
      document.body.appendChild(root)
    }
    return root
  }
}