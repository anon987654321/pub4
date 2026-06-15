import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select"]

  switch() {
    const domain = this.selectTarget.value
    if (!domain) return

    const form = document.createElement("form")
    form.method = "post"
    form.action = this.selectTarget.dataset.url

    const method = document.createElement("input")
    method.type = "hidden"
    method.name = "_method"
    method.value = "patch"
    form.appendChild(method)

    const token = document.querySelector("meta[name='csrf-token']")?.content
    if (token) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "authenticity_token"
      input.value = token
      form.appendChild(input)
    }

    const domainInput = document.createElement("input")
    domainInput.type = "hidden"
    domainInput.name = "domain"
    domainInput.value = domain
    form.appendChild(domainInput)

    document.body.appendChild(form)
    form.submit()
  }
}