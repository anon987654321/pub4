import { Controller } from "@hotwired/stimulus"

// vYroQxg: $(".search input").on("focus blur") → toggle .focus on .search
export default class extends Controller {
  focus() {
    this.element.classList.add("focus")
  }

  blur() {
    this.element.classList.remove("focus")
  }
}
