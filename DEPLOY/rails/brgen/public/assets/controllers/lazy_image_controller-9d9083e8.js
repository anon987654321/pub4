// Lazy image controller — IntersectionObserver based, with blurhash placeholder support (AN506).
// Micro cosmetic: smooth fade-in, respects reduced-motion, low impact.
import { Controller } from "@hotwired/stimulus"

const BASE83 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"

export default class extends Controller {
  static targets = ["image"]
  static values = { src: String, blurhash: String }

  connect() {
    if (this.hasImageTarget) {
      this.observer = new IntersectionObserver(this.load.bind(this), {
        rootMargin: "200px"
      })
      this.observer.observe(this.imageTarget)
    }
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  load(entries) {
    entries.forEach(entry => {
      if (entry.isIntersecting && this.hasImageTarget) {
        const img = this.imageTarget
        const originalSrc = this.srcValue || img.dataset.src
        if (!originalSrc) return

        // Optional blurhash canvas placeholder (if provided via data)
        if (this.blurhashValue && !img.complete) {
          this.renderBlurhashPlaceholder(img, this.blurhashValue)
        }

        img.src = originalSrc
        img.classList.add("lazy-loaded")

        img.onload = () => {
          img.classList.add("lazy-fade-in")
          if (this.observer) this.observer.unobserve(img)
        }

        delete img.dataset.src
      }
    })
  }

  renderBlurhashPlaceholder(img, hash) {
    const decoded = this.decodeBlurhash(hash)
    const canvas = document.createElement("canvas")
    canvas.width = decoded?.width || 32
    canvas.height = decoded?.height || 32
    const ctx = canvas.getContext("2d", { alpha: true })
    if (decoded?.pixels?.length) {
      const imageData = ctx.createImageData(canvas.width, canvas.height)
      imageData.data.set(decoded.pixels)
      ctx.putImageData(imageData, 0, 0)
    } else {
      ctx.fillStyle = "#222"
      ctx.fillRect(0, 0, canvas.width, canvas.height)
    }
    const dataUrl = canvas.toDataURL()
    img.style.backgroundImage = `url(${dataUrl})`
    img.style.backgroundSize = "cover"
    img.style.transition = "opacity 240ms ease"
  }

  decodeBlurhash(hash) {
    if (!hash || hash.length < 6) return null
    const sizeFlag = this.decode83(hash[0])
    const componentsX = (sizeFlag % 9) + 1
    const componentsY = Math.floor(sizeFlag / 9) + 1
    const quantMaxValue = this.decode83(hash[1])
    const maxValue = (quantMaxValue + 1) / 166
    const colors = new Array(componentsX * componentsY)

    colors[0] = this.decodeDC(this.decode83(hash.slice(2, 6)))
    let idx = 6
    for (let i = 1; i < colors.length; i++) {
      colors[i] = this.decodeAC(this.decode83(hash.slice(idx, idx + 2)), maxValue)
      idx += 2
    }

    const width = 32
    const height = 32
    const pixels = new Uint8ClampedArray(width * height * 4)
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        let r = 0
        let g = 0
        let b = 0
        for (let j = 0; j < componentsY; j++) {
          for (let i = 0; i < componentsX; i++) {
            const basis = Math.cos(Math.PI * x * i / width) * Math.cos(Math.PI * y * j / height)
            const c = colors[j * componentsX + i]
            r += c[0] * basis
            g += c[1] * basis
            b += c[2] * basis
          }
        }
        const p = (y * width + x) * 4
        pixels[p] = this.linearToSrgb(r)
        pixels[p + 1] = this.linearToSrgb(g)
        pixels[p + 2] = this.linearToSrgb(b)
        pixels[p + 3] = 255
      }
    }
    return { width, height, pixels }
  }

  decode83(str) {
    let value = 0
    for (const char of String(str || "")) {
      value = value * 83 + BASE83.indexOf(char)
    }
    return value
  }

  decodeDC(value) {
    const r = value >> 16
    const g = (value >> 8) & 255
    const b = value & 255
    return [this.srgbToLinear(r), this.srgbToLinear(g), this.srgbToLinear(b)]
  }

  decodeAC(value, maximumValue) {
    const quantR = Math.floor(value / 361)
    const quantG = Math.floor(value / 19) % 19
    const quantB = value % 19
    return [
      this.signPow((quantR - 9) / 9, 2) * maximumValue,
      this.signPow((quantG - 9) / 9, 2) * maximumValue,
      this.signPow((quantB - 9) / 9, 2) * maximumValue
    ]
  }

  srgbToLinear(value) {
    const v = value / 255
    if (v <= 0.04045) return v / 12.92
    return ((v + 0.055) / 1.055) ** 2.4
  }

  linearToSrgb(value) {
    const v = Math.max(0, Math.min(1, value))
    const srgb = v <= 0.0031308 ? v * 12.92 : 1.055 * (v ** (1 / 2.4)) - 0.055
    return Math.max(0, Math.min(255, Math.round(srgb * 255)))
  }

  signPow(value, exponent) {
    return value < 0 ? -((-value) ** exponent) : value ** exponent
  }
}
