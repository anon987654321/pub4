import ScrollReveal from "@stimulus-components/scroll-reveal"

export default class extends ScrollReveal {
  get defaultOptions() {
    return {
      class: "is-visible",
      threshold: 0.12,
      rootMargin: "0px 0px -10% 0px"
    }
  }
}
