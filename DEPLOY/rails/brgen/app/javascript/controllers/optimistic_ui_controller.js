import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static classes = ["active"]

  activate() {
    this.element.classList.add(this.activeClass || "is-active")
  }

  revert() {
    this.element.classList.remove(this.activeClass || "is-active")
  }
}