import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.replaying = false
    this.onSubmit = this.submit.bind(this)
    this.onSubmitEnd = this.unlock.bind(this)
    this.element.addEventListener("submit", this.onSubmit)
    // A failed submit (validation, 422, dropped connection) must not leave the
    // button dead forever, and Turbo restores this form from cache on back.
    this.element.addEventListener("turbo:submit-end", this.onSubmitEnd)
    document.addEventListener("turbo:before-cache", this.onSubmitEnd)
    this.unlock()
  }

  disconnect() {
    this.element.removeEventListener("submit", this.onSubmit)
    this.element.removeEventListener("turbo:submit-end", this.onSubmitEnd)
    document.removeEventListener("turbo:before-cache", this.onSubmitEnd)
  }

  // Double-submit guard. Two composer forms have carried
  // `submit->form-submit#lock` since they were written and this method did not
  // exist, so on a slow connection every extra tap posted another copy.
  //
  // The disable is deferred a tick on purpose: a submit button that is already
  // disabled while the submit event is still dispatching drops its own
  // name/value from the entry list, and Turbo reads the submitter from its own
  // listener whose order relative to this one is not defined. Nothing can tap
  // twice inside one tick, so deferring costs no protection.
  //
  // Idempotent — submit() replays the event through requestSubmit(), so this
  // fires twice per real submission.
  lock() {
    this.locked = true
    setTimeout(() => { if (this.locked) this._setDisabled(true) }, 0)
  }

  unlock() {
    this.locked = false
    this._setDisabled(false)
  }

  _setDisabled(state) {
    this._submitters().forEach((button) => {
      button.disabled = state
      if (state) button.setAttribute("aria-busy", "true")
      else button.removeAttribute("aria-busy")
    })
  }

  _submitters() {
    return Array.from(this.element.querySelectorAll('button[type="submit"], input[type="submit"]'))
  }

  submit(event) {
    if (this.replaying) return
    const errors = this.validate()
    if (errors.length) {
      event.preventDefault()
      this.renderErrors(errors)
      // Nothing was sent, so lock() (a separate submit action on the same
      // event) must not leave the button dead.
      this.unlock()
      return
    }

    if (typeof this.element.requestSubmit === "function") {
      event.preventDefault()
      this.replaying = true
      this.clearErrors()
      this.element.requestSubmit()
      setTimeout(() => { this.replaying = false }, 0)
    }
  }

  validate() {
    const errors = []
    const title = this.element.querySelector('[name$="[title]"]')
    const content = this.element.querySelector('[name$="[content]"]')

    if (title && !title.value.trim()) {
      errors.push({ field: title, message: "Title is required." })
    }

    if (content?.hasAttribute("data-validate-nonempty") && !content.value.trim()) {
      errors.push({ field: content, message: "Please add a short description." })
    }

    return errors
  }

  renderErrors(errors) {
    this.clearErrors()
    const wrap = this._errorWrap()
    const list = document.createElement("ul")
    list.className = "form-inline-errors"
    errors.forEach(({ field, message }) => {
      field.setCustomValidity(message)
      field.classList.add("field-error")
      const item = document.createElement("li")
      item.textContent = message
      list.appendChild(item)
      field.addEventListener("input", () => {
        field.setCustomValidity("")
        field.classList.remove("field-error")
        this.clearErrors()
      }, { once: true })
    })
    wrap.replaceChildren(list)
  }

  clearErrors() {
    this.element.querySelectorAll(".field-error").forEach(field => field.classList.remove("field-error"))
    this.element.querySelectorAll("input, textarea, select").forEach(field => {
      if (typeof field.setCustomValidity === "function") field.setCustomValidity("")
    })
    const wrap = this.element.querySelector("[data-form-submit-target='errors']")
    if (wrap) wrap.textContent = ""
  }

  _errorWrap() {
    let wrap = this.element.querySelector("[data-form-submit-target='errors']")
    if (!wrap) {
      wrap = document.createElement("div")
      wrap.className = "form-inline-errors-wrap"
      wrap.dataset.formSubmitTarget = "errors"
      this.element.prepend(wrap)
    }
    return wrap
  }
}
