import { Controller } from "@hotwired/stimulus"

// The tab bar is data-turbo-permanent, so Turbo keeps the first page's element,
// and the aria-current it was rendered with, across every visit. This marks the
// tab for the page actually showing after each one.
export default class extends Controller {
  connect() {
    this.mark = () => this.#markCurrent()
    document.addEventListener("turbo:load", this.mark)
    this.#markCurrent()
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.mark)
  }

  #markCurrent() {
    const here = window.location.pathname
    this.element.querySelectorAll("a[href]").forEach((link) => {
      const path = new URL(link.getAttribute("href"), window.location.origin).pathname
      if (path === here) link.setAttribute("aria-current", "page")
      else link.removeAttribute("aria-current")
    })
  }
}
