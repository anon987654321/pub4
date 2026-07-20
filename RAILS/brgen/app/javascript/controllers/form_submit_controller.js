import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.replaying = false
    this.onSubmit = this.submit.bind(this)
    this.element.addEventListener("submit", this.onSubmit)
  }

  disconnect() {
    this.element.removeEventListener("submit", this.onSubmit)
  }

  submit(event) {
    if (this.replaying) return
    const errors = this.validate()
    if (errors.length) {
      event.preventDefault()
      this.renderErrors(errors)
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
