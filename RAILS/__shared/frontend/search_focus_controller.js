import { Controller } from "@hotwired/stimulus"

// vYroQxg: $(".search input").on("focus blur") → toggle .focus on .search.
// Listened for on the shell itself (focusin/focusout bubble, focus/blur do not),
// so a field inside it needs no wiring of its own: wrapping any search input in
// <div class="search" data-controller="search-focus"> is the whole adoption.
// The explicit focus->/blur-> actions some fields still carry call the same
// idempotent methods.
export default class extends Controller {
  connect() {
    this.onIn = () => this.focus()
    this.onOut = (event) => {
      if (!this.element.contains(event.relatedTarget)) this.blur()
    }
    this.element.addEventListener("focusin", this.onIn)
    this.element.addEventListener("focusout", this.onOut)
  }

  disconnect() {
    this.element.removeEventListener("focusin", this.onIn)
    this.element.removeEventListener("focusout", this.onOut)
  }

  focus() {
    this.element.classList.add("focus")
  }

  blur() {
    this.element.classList.remove("focus")
  }
}
