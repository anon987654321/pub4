import { Controller } from "@hotwired/stimulus"

// jOxVvNE frame opacity loop (exact anime timeline).
let animePromise = null
function loadAnime() {
  if (globalThis.anime) return Promise.resolve(globalThis.anime)
  if (animePromise) return animePromise
  animePromise = import("https://esm.sh/animejs@3.2.1")
    .then((mod) => {
      const anime = mod.default || mod.anime || mod
      globalThis.anime = anime
      return anime
    })
    .catch(() => null)
  return animePromise
}

export default class extends Controller {
  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.element.querySelectorAll(".frames div").forEach((el) => {
        el.style.opacity = "1"
      })
      return
    }
    loadAnime().then((anime) => {
      if (!anime) return
      anime
        .timeline({ loop: true })
        .add({
          targets: this.element.querySelector(".frames div:nth-of-type(1)"),
          opacity: 1,
          delay: 100,
        })
        .add({
          targets: this.element.querySelector(".frames div:nth-of-type(2)"),
          opacity: 1,
          delay: 100,
        })
        .add({
          targets: this.element.querySelector(".frames div:nth-of-type(3)"),
          opacity: 1,
          delay: 100,
          endDelay: 4000,
        })
    })
  }
}
