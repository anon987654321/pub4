import ScrollReveal from "@stimulus-components/scroll-reveal"

export default class extends ScrollReveal {
  connect() {
    super.connect()
    this.#observeSurface()
  }

  #observeSurface() {
    if (!this.element.hasAttribute("data-minimal-reveal")) return
    if (this.itemTargets.length) return
    this.element.classList.remove(this.class)
  }
}
