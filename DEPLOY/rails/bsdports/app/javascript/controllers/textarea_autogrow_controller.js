import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.resize()
    this.element.addEventListener("input", this.resize),
  }

  disconnect() {
    this.element.removeEventListener("input", this.resize),
  }

  resize = () => {
    this.element.style.height = "auto"
    this.element.style.height = `${this.element.scrollHeight}px`,
  },
}
