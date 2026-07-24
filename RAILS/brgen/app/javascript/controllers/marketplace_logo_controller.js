import { Controller } from "@hotwired/stimulus"

// zYaJege timelines (anime.js) — same targets/delays/easings as the pen.
// Vanilla DOM instead of jQuery; anime loaded once from esm CDN.
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

function setDashoffset(el) {
  const length = el.getTotalLength ? el.getTotalLength() : 0
  el.style.strokeDasharray = length
  el.style.strokeDashoffset = length
  return length
}

export default class extends Controller {
  static targets = ["wrapper", "banner", "smiley", "smileyPath", "cart", "cartPath", "number", "seedPlus"]

  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.#staticEndState()
      return
    }
    loadAnime().then((anime) => {
      if (!anime || !this.hasBannerTarget) return
      this.#run(anime)
    })
  }

  disconnect() {
    this.animations?.forEach((a) => a.pause?.())
    this.animations = []
  }

  #staticEndState() {
    if (this.hasSmileyTarget) this.smileyTarget.style.opacity = "0"
    if (this.hasCartTarget) this.cartTarget.style.opacity = "1"
    if (this.hasNumberTarget) {
      this.numberTarget.style.opacity = "1"
      this.numberTarget.textContent = "9+"
    }
  }

  #run(anime) {
    const smileyPaths = this.smileyPathTargets
    const cartPaths = this.cartPathTargets
    const blinkPaths = smileyPaths.filter((el) => el.dataset.marketplaceLogoBlinkParam === "true")

    smileyPaths.forEach((el) => {
      try {
        const href = el.getAttribute("href") || el.getAttribute("xlink:href")
        const path = href && this.element.querySelector(href)
        if (path?.getTotalLength) {
          const len = path.getTotalLength()
          el.style.strokeDasharray = len
          el.style.strokeDashoffset = len
        }
      } catch (_) {
        /* use elements may not resolve length in all engines */
      }
    })

    const smileyface = anime
      .timeline()
      .add({
        targets: smileyPaths,
        strokeDashoffset: [setDashoffset, 0],
        delay: (_el, i) => i * 250,
        easing: "easeInOutSine",
        duration: 600,
      })
      .add({
        targets: blinkPaths,
        opacity: 0,
      })
      .add({
        targets: blinkPaths,
        opacity: 1,
      })
      .add({
        targets: this.smileyTarget,
        opacity: 0,
      })

    // Source pen switches banner bg #fe9900 → #000; header placement keeps transparent.
    const switchStroke = anime
      .timeline({
        targets: smileyPaths,
      })
      .add({
        stroke: "#000",
        strokeWidth: 3,
        delay: 2200,
      })
      .add({
        stroke: "#fff",
        strokeWidth: 2,
      })

    const shoppingCart = anime
      .timeline()
      .add({
        targets: this.cartTarget,
        delay: 3500,
        opacity: 1,
      })
      .add({
        targets: cartPaths,
        strokeDashoffset: [setDashoffset, 0],
        delay: (_el, i) => i * 250,
        easing: "easeInOutSine",
        duration: 600,
      })
      .add({
        targets: this.numberTarget,
        opacity: 1,
      })
      .add({
        targets: this.numberTarget,
        duration: 3000,
        round: 1,
        easing: "easeInOutQuad",
        complete: () => this.#burst(anime),
        textContent: 9
      })

    this.animations = [smileyface, switchStroke, shoppingCart]
  }

  #burst(anime) {
    if (!this.hasNumberTarget || !this.hasBannerTarget) return
    const plus = document.createElement("span")
    plus.textContent = "+"
    this.numberTarget.appendChild(plus)

    for (let i = 1; i <= 40; i++) {
      const span = document.createElement("span")
      span.textContent = "+"
      this.bannerTarget.appendChild(span)
    }

    const extras = this.bannerTarget.querySelectorAll(":scope > span")
    anime
      .timeline()
      .add({
        targets: this.numberTarget.querySelector("span"),
        opacity: 1,
        rotate: 180,
        duration: 1400,
      })
      .add({
        targets: extras,
        opacity: [1, 0],
        translateX: () => anime.random(-100, 100),
        translateY: () => anime.random(-300, 0),
        rotate: () => anime.random(-45, 45),
        scale: () => anime.random(8, 18),
        easing: "easeInOutBack",
        delay: anime.stagger(80),
        duration: 6000,
      })
  }
}
