// X-style action controller for brgen subapps
// Handles optimistic updates for likes, reposts, saves, votes etc.
// Matches x.com interaction patterns (hover accent, live counts)

import { Controller } from "@hotwired/stimulus"
import Haptics from "pub4/haptics"

export default class extends Controller {
  static targets = ["count"]
  static values = {
    url: String,
    count: Number,
    activeClass: { type: String, default: "active" },
    param: { type: String, default: "" },
    paramKey: { type: String, default: "vote[value]" },
    // shared/_action_bar's like button writes both of these, and neither was
    // declared — so Stimulus never read them and the POST carried no subject.
    // Shared::ReactionsController#create opens with
    // params.require(:target_gid), which raises ParameterMissing → 400, so
    // every like optimistically toggled, got rejected, and _rollback reverted
    // it. The button could not work.
    targetGid: { type: String, default: "" },
    kind: { type: String, default: "" },
    errorMessage: { type: String, default: "That action could not be saved. Please try again." }
  }

  connect() {
    this.originalCount = this.countValue ?? 0
  }

  press(event) {
    if (event?.button != null && event.button !== 0) return
    if (this.element.matches(":disabled, [aria-disabled='true']")) return
    this.element.classList.add("interaction-stateful")
    this.element.dataset.interactionState = "pressed"
    Haptics.pulse(8)
  }

  toggle(event) {

    event.preventDefault()
    const button = event.currentTarget || this.element
    const isActive = button.classList.contains(this.activeClassValue)

    button.classList.toggle(this.activeClassValue, !isActive)

    if (this.hasCountTarget) {
      const delta = isActive ? -1 : 1
      this.countValue = (this.countValue ?? 0) + delta
      this.countTarget.textContent = this.countValue
    }

    if (this.urlValue) {
      this.element.classList.add("interaction-stateful")
      this.element.dataset.interactionState = "working"
      this.element.setAttribute("aria-busy", "true")

      const headers = {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
        "Accept": "text/vnd.turbo-stream.html, application/json"
      }
      const init = { method: "POST", headers, credentials: "same-origin" }
      const body = new URLSearchParams()
      if (this.paramValue) body.append(this.paramKeyValue, this.paramValue)
      if (this.targetGidValue) body.append("target_gid", this.targetGidValue)
      if (this.kindValue) body.append("kind", this.kindValue)
      if (body.toString()) {
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        init.body = body.toString()
      }
      fetch(this.urlValue, init).then(res => {
        if (res.ok) {
          this._succeeded(button)
        } else {
          this._failed(button, isActive)
        }
      }).catch(() => this._failed(button, isActive))
    } else if (button.dataset.interactionState === "pressed") {
      button.dataset.interactionState = "idle"
    }
  }

  _succeeded(button) {
    button.dataset.interactionState = "confirmed"
    button.removeAttribute("aria-busy")
    Haptics.pulse([12, 30, 12])
    window.setTimeout(() => {
      if (button.dataset.interactionState === "confirmed") {
        button.dataset.interactionState = "idle"
      }
    }, 260)
  }

  _failed(button, wasActive) {
    this._rollback(button, wasActive)
    button.dataset.interactionState = "error"
    button.removeAttribute("aria-busy")
    this._notify(this.errorMessageValue)
    window.setTimeout(() => {
      if (button.dataset.interactionState === "error") {
        button.dataset.interactionState = "idle"
      }
    }, 400)
  }

  _rollback(button, wasActive) {
    button.classList.toggle(this.activeClassValue, wasActive)
    if (this.hasCountTarget) {
      this.countValue = this.originalCount
      this.countTarget.textContent = this.originalCount
    }
  }

  _notify(message) {
    const stack = document.querySelector(".toast-stack") || this._createToastStack()
    const toast = document.createElement("div")
    toast.className = "toast"
    toast.dataset.variant = "error"
    toast.setAttribute("role", "alert")
    toast.setAttribute("aria-live", "assertive")
    toast.dataset.controller = "toast"
    toast.dataset.toastDelayValue = "4000"
    toast.setAttribute("data-turbo-temporary", "")
    toast.textContent = message
    stack.append(toast)
  }

  _createToastStack() {
    const stack = document.createElement("div")
    stack.className = "toast-stack"
    document.body.append(stack)
    return stack
  }
}
