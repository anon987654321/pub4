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

  press() {
    if (this.element.matches(":disabled, [aria-disabled='true']")) return
    this.element.classList.add("interaction-stateful")
    this.element.dataset.interactionState = "pressed"
    Haptics.pulse(8)
  }

  toggle(event) {

    event.preventDefault()
    const btn = event.currentTarget || this.element
    const isActive = btn.classList.contains(this.activeClassValue)

    btn.classList.toggle(this.activeClassValue, !isActive)

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
          this._succeeded(btn)
        } else {
          this._failed(btn, isActive)
        }
      }).catch(() => this._failed(btn, isActive))
    }
  }

  _succeeded(btn) {
    btn.dataset.interactionState = "confirmed"
    btn.removeAttribute("aria-busy")
    Haptics.pulse([12, 30, 12])
    window.setTimeout(() => {
      if (btn.dataset.interactionState === "confirmed") {
        btn.dataset.interactionState = "idle"
      }
    }, 260)
  }

  _failed(btn, wasActive) {
    this._rollback(btn, wasActive)
    btn.dataset.interactionState = "error"
    btn.removeAttribute("aria-busy")
    this._notify(this.errorMessageValue)
    window.setTimeout(() => {
      if (btn.dataset.interactionState === "error") {
        btn.dataset.interactionState = "idle"
      }
    }, 400)
  }

  _rollback(btn, wasActive) {
    btn.classList.toggle(this.activeClassValue, wasActive)
    if (this.hasCountTarget) {
      this.countValue = this.originalCount
      this.countTarget.textContent = this.originalCount
    }
  }

  _notify(message) {
    const stack = document.querySelector(".toast-stack") || this._createToastStack()
    const toast = document.createElement("div")
    toast.className = "toast toast--error"
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
