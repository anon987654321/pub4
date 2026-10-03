import { Controller } from "@hotwired/stimulus"

// positron, not liberty. Both are light -- liberty's background is #f8f4f0 and
// positron's is rgb(242,243,240), so this was never a dark-to-light change --
// but liberty carries 111 styled layers of colourful cartography and positron
// carries 55 desaturated ones. Positron is drawn to sit UNDER data rather than
// to be read for itself, which is the same argument the rest of this design
// system makes about chrome.
const DEFAULT_STYLE = "https://tiles.openfreemap.org/styles/positron"

export default class extends Controller {
  static targets = ["canvas", "search", "popup"]
  static values = {
    centerLat: Number,
    centerLng: Number,
    zoom: Number,
    styleUrl: String,
    points: Array
  }

  connect() {
    this.points = this.hasPointsValue ? this.pointsValue : this._readPoints()
    this.markers = []
    this.map = null
    this._boundSearch = this.filterPoints.bind(this)
    this._boot()
  }

  disconnect() {
    this._destroy()
  }

  _rootCanvas() {
    if (this.hasCanvasTarget) return this.canvasTarget
    return this.element.querySelector("#map")
  }

  _readPoints() {
    try {
      const raw = this.element.dataset.mapPointsValue || this.element.dataset.mapPoints || "[]"
      const parsed = JSON.parse(raw)
      return Array.isArray(parsed) ? parsed : []
    } catch (_) {
      return []
    }
  }

  _center() {
    const lat = this.hasCenterLatValue ? this.centerLatValue : 60.39299
    const lng = this.hasCenterLngValue ? this.centerLngValue : 5.32415
    return [lng, lat]
  }

  _styleUrl() {
    return this.hasStyleUrlValue && this.styleUrlValue ? this.styleUrlValue : DEFAULT_STYLE
  }

  _boot() {
    const canvas = this._rootCanvas()
    if (!canvas) return this._fallback()
    if (!window.maplibregl) return this._fallback()

    window.maplibregl.accessToken = ""
    this.map = new window.maplibregl.Map({
      container: canvas,
      style: this._styleUrl(),
      center: this._center(),
      zoom: this.hasZoomValue ? this.zoomValue : 12.2,
      pitch: 55,
      bearing: -14,
      antialias: true
    })

    this.map.addControl(new window.maplibregl.NavigationControl({ visualizePitch: true }), "bottom-right")
    this.map.addControl(new window.maplibregl.GeolocateControl({
      positionOptions: { enableHighAccuracy: true },
      trackUserLocation: true,
      showUserHeading: true
    }), "bottom-right")

    this.map.on("load", () => this._render())

    if (this.hasSearchTarget) {
      this.searchTarget.addEventListener("input", this._boundSearch)
    }
  }

  _destroy() {
    if (this.hasSearchTarget) {
      this.searchTarget.removeEventListener("input", this._boundSearch)
    }
    this.markers.forEach(marker => marker.remove())
    this.markers = []
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  _render(list = this.points) {
    if (!this.map) return
    this.markers.forEach(marker => marker.remove())
    this.markers = []

    list.forEach(point => {
      const lat = Number(point.lat)
      const lng = Number(point.lng)
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return

      const marker = document.createElement("div")
      marker.className = `map-marker map-marker--${point.type || "resource"}`
      marker.setAttribute("aria-label", point.title || "Map point")
      marker.tabIndex = 0
      marker.title = point.title || "Map point"
      marker.innerHTML = `<span></span>`

      const popup = new window.maplibregl.Popup({ offset: 20 }).setHTML(this._popupHtml(point))
      const instance = new window.maplibregl.Marker({ element: marker, anchor: "bottom" })
        .setLngLat([lng, lat])
        .setPopup(popup)
        .addTo(this.map)

      marker.addEventListener("click", () => popup.addTo(this.map))
      marker.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault()
          popup.addTo(this.map)
        }
      })

      this.markers.push(instance)
    })
  }

  _popupHtml(point) {
    const title = this._escape(point.title || "Map point")
    const subtitle = this._escape(point.subtitle || "")
    const url = this._escape(point.url || "#")
    return `
      <div class="map-popup">
        <strong>${title}</strong>
        ${subtitle ? `<p>${subtitle}</p>` : ""}
        <a href="${url}">Open</a>
      </div>
    `
  }

  _escape(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }

  filterPoints() {
    if (!this.hasSearchTarget) return
    const q = this.searchTarget.value.trim().toLowerCase()
    if (!q) {
      this._render(this.points)
      return
    }
    this._render(this.points.filter(point => {
      const haystack = [point.title, point.subtitle, point.type, point.city, point.kind]
        .filter(Boolean)
        .join(" ")
        .toLowerCase()
      return haystack.includes(q)
    }))
  }

  _fallback() {
    const canvas = this._rootCanvas()
    if (!canvas) return
    canvas.classList.add("map-fallback")
    canvas.innerHTML = this.points.map(point => `
      <a href="${this._escape(point.url || "#")}">
        <span>${this._escape(point.type || "point")}</span>
        <strong>${this._escape(point.title || "Map point")}</strong>
        <small>${this._escape(point.subtitle || "")}</small>
      </a>
    `).join("") || "<p>No map points yet.</p>"
  }
}
