import { Controller } from "@hotwired/stimulus"

const BASE = "https://cdn.jsdelivr.net/npm/lightgallery@2.7.2"
const CORE = `${BASE}/lightgallery.umd.min.js`
const THUMBNAIL = `${BASE}/plugins/thumbnail/lg-thumbnail.umd.min.js`
const ZOOM = `${BASE}/plugins/zoom/lg-zoom.umd.min.js`
const STYLES = `${BASE}/css/lightgallery-bundle.min.css`

function loadScript(src) {
  const existing = document.querySelector(`script[data-lightgallery-src="${src}"]`)
  if (existing?.dataset.loaded === "true") return Promise.resolve()
  if (existing) return new Promise((resolve, reject) => {
    existing.addEventListener("load", resolve, { once: true })
    existing.addEventListener("error", reject, { once: true })
  })

  return new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = src
    script.async = false
    script.crossOrigin = "anonymous"
    script.dataset.lightgallerySrc = src
    script.addEventListener("load", () => {
      script.dataset.loaded = "true"
      resolve()
    }, { once: true })
    script.addEventListener("error", reject, { once: true })
    document.head.append(script)
  })
}

function loadStyles() {
  if (document.querySelector('link[data-lightgallery-styles="true"]')) return Promise.resolve()
  return new Promise((resolve, reject) => {
    const link = document.createElement("link")
    link.rel = "stylesheet"
    link.href = STYLES
    link.crossOrigin = "anonymous"
    link.dataset.lightgalleryStyles = "true"
    link.addEventListener("load", resolve, { once: true })
    link.addEventListener("error", reject, { once: true })
    document.head.append(link)
  })
}

export default class extends Controller {
  async open(event) {
    const anchor = event.target.closest("a[data-gallery-item]")
    if (!anchor || !this.element.contains(anchor)) return

    event.preventDefault()
    const anchors = [...this.element.querySelectorAll("a[data-gallery-item]")]
    const index = anchors.indexOf(anchor)

    try {
      await loadStyles()
      await loadScript(CORE)
      await loadScript(THUMBNAIL)
      await loadScript(ZOOM)

      if (!window.lightGallery || !window.lgThumbnail || !window.lgZoom) {
        throw new Error("LightGallery did not expose its plugins.")
      }

      if (!this.gallery) {
        this.gallery = window.lightGallery(this.element, {
          selector: "a[data-gallery-item]",
          plugins: [window.lgThumbnail, window.lgZoom],
          licenseKey: document.querySelector('meta[name="lg-license"]')?.content || "0000-0000-000-0000",
          speed: 250,
          download: false,
          thumbnail: true,
          zoom: true,
          mobileSettings: { controls: true, showCloseIcon: true, download: false }
        })
      }
      this.gallery.openGallery(index)
    } catch {
      // The anchor remains a real image URL when the optional gallery cannot load.
      window.open(anchor.href, "_blank", "noopener,noreferrer")
    }
  }

  disconnect() {
    this.gallery?.destroy(true)
    this.gallery = null
  }
}
