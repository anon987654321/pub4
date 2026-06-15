import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { hash: String, width: Number, height: Number }

  connect() {
    if (!this.hashValue || !window.decodeBlurHash) return
    const canvas = document.createElement("canvas")
    canvas.width = this.widthValue || 32
    canvas.height = this.heightValue || 32
    const pixels = window.decodeBlurHash(this.hashValue, canvas.width, canvas.height)
    const ctx = canvas.getContext("2d")
    const imageData = ctx.createImageData(canvas.width, canvas.height)
    imageData.data.set(pixels)
    ctx.putImageData(imageData, 0, 0)
    this.element.style.backgroundImage = `url(${canvas.toDataURL()})`
  }
}