import { Controller } from "@hotwired/stimulus"

const DEFAULT_STYLE = "https://tiles.openfreemap.org/styles/liberty"

export default class extends Controller {
  static targets = ["canvas"]
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
    this._boot()
  }

  disconnect() {
    this.markers.forEach(marker => marker.remove())
    this.markers = []
    if (this.map) this.map.remove()
  }

  _rootCanvas() {
    if (this.hasCanvasTarget) return this.canvasTarget
    return this.element.querySelector("#hjerterom-map")
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
    const lat = this.hasCenterLatValue ? this.centerLatValue : 60.4669
    const lng = this.hasCenterLngValue ? this.centerLngValue : 5.3256
    return [lng, lat]
  }

  _styleUrl() {
    return this.hasStyleUrlValue && this.styleUrlValue ? this.styleUrlValue : DEFAULT_STYLE
  }

  _boot() {
    const canvas = this._rootCanvas()
    if (!canvas || !window.maplibregl) return this._fallback()

    window.maplibregl.accessToken = ""
    this.map = new window.maplibregl.Map({
      container: canvas,
      style: this._styleUrl(),
      center: this._center(),
      zoom: this.hasZoomValue ? this.zoomValue : 11.7,
      pitch: 56,
      bearing: -18,
      antialias: true
    })

    this.map.addControl(new window.maplibregl.NavigationControl({ visualizePitch: true }), "bottom-right")
    this.map.addControl(new window.maplibregl.GeolocateControl({
      positionOptions: { enableHighAccuracy: true },
      trackUserLocation: true,
      showUserHeading: true
    }), "bottom-right")

    this.map.on("load", () => {
      this.points.forEach(point => {
        const lat = Number(point.lat)
        const lng = Number(point.lng)
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) return

        const marker = document.createElement("a")
        marker.href = point.url || "#"
        marker.className = `hjerterom-heart-marker hjerterom-heart-marker--${point.type || "resource"}`
        marker.setAttribute("aria-label", point.title || "Hjerterom punkt")
        marker.innerHTML = `<span class="hjerterom-heart-marker__heart"></span><span class="hjerterom-heart-marker__pulse"></span>`

        const popup = new window.maplibregl.Popup({ offset: 28 }).setHTML(`
          <div class="map-popup">
            <strong>${this._escape(point.title || "Hjerterom punkt")}</strong>
            <p>${this._escape(point.subtitle || "Åsane")}</p>
            <a href="${this._escape(point.url || "#")}">Open</a>
          </div>
        `)

        const instance = new window.maplibregl.Marker({ element: marker, anchor: "bottom" })
          .setLngLat([lng, lat])
          .setPopup(popup)
          .addTo(this.map)

        this.markers.push(instance)
      })
    })
  }

  _fallback() {
    const canvas = this._rootCanvas()
    if (!canvas) return
    canvas.innerHTML = this.points.map(point => `
      <a class="map-home__pin-card" href="${this._escape(point.url || "#")}">
        <span>${this._escape(point.type || "point")}</span>
        <strong>${this._escape(point.title || "Hjerterom punkt")}</strong>
        <small>${this._escape(point.subtitle || "")}</small>
      </a>
    `).join("") || "<p>Ingen kartpunkter ennå.</p>"
    canvas.classList.add("map-home__fallback")
  }

  _escape(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
