import { Controller } from "@hotwired/stimulus"

// Mapbox map with place markers and optional search (brgen maps, hjerterom delivery zones).
export default class extends Controller {
  static targets = ["canvas", "search", "popup"]
  static values = {
    token: String,
    places: { type: Array, default: [] },
    center: { type: Array, default: [5.33, 60.39] },
    zoom: { type: Number, default: 12 },
    style: { type: String, default: "mapbox://styles/mapbox/dark-v11" },
    pitch: { type: Number, default: 0 },
    bearing: { type: Number, default: 0 }
  }

  connect() {
    this.markers = []
    this.#boot()
    document.addEventListener("click", this.#handleOutsideClick)
    if (this.hasSearchTarget) {
      this.searchTarget.addEventListener("input", this.#handleSearch)
    }
  }

  disconnect() {
    document.removeEventListener("click", this.#handleOutsideClick)
    if (this.hasSearchTarget) {
      this.searchTarget.removeEventListener("input", this.#handleSearch)
    }
    this.#clearMarkers()
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  #boot() {
    if (!this.hasCanvasTarget || !window.mapboxgl || !this.tokenValue) return

    window.mapboxgl.accessToken = this.tokenValue
    this.map = new window.mapboxgl.Map({
      container: this.canvasTarget,
      style: this.styleValue,
      center: this.centerValue,
      zoom: this.zoomValue,
      pitch: this.pitchValue,
      bearing: this.bearingValue
    })

    this.map.addControl(new window.mapboxgl.NavigationControl({ visualizePitch: true }), "bottom-right")
    this.map.addControl(new window.mapboxgl.GeolocateControl({
      positionOptions: { enableHighAccuracy: true },
      trackUserLocation: true,
      showUserHeading: true
    }), "bottom-right")

    this.map.on("load", () => this.#renderMarkers(this.placesValue))
  }

  #renderMarkers(list) {
    if (!this.map) return
    this.#clearMarkers()

    list.forEach(place => {
      const lat = Number(place.lat)
      const lng = Number(place.lng)
      if (!lat || !lng) return

      const el = document.createElement("div")
      el.className = "map-marker"
      el.style.cssText = "width:10px;height:10px;border-radius:50%;background:var(--accent,#fff);border:2px solid #000;cursor:pointer"

      const marker = new window.mapboxgl.Marker(el).setLngLat([lng, lat]).addTo(this.map)

      if (place.popupHtml) {
        marker.setPopup(new window.mapboxgl.Popup({ offset: 28 }).setHTML(place.popupHtml))
      }

      el.addEventListener("click", () => {
        this.map.flyTo({ center: [lng, lat], zoom: Math.max(this.zoomValue, 14) })
        if (this.hasPopupTarget) {
          this.popupTarget.style.display = "block"
          this.popupTarget.innerHTML = place.popupHtml || this.#defaultPopup(place)
        }
      })

      this.markers.push(marker)
    })
  }

  #defaultPopup(place) {
    const name = this.#escape(place.name || place.title || "Place")
    const meta = this.#escape([place.kind, place.neighborhood, place.subtitle].filter(Boolean).join(" · "))
    return `<strong>${name}</strong>${meta ? `<br><span style="opacity:.6">${meta}</span>` : ""}`
  }

  #escape(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }

  #clearMarkers() {
    this.markers.forEach(marker => marker.remove())
    this.markers = []
  }

  #handleSearch = (event) => {
    const query = event.target.value.toLowerCase()
    const filtered = query
      ? this.placesValue.filter(place => {
          const name = (place.name || place.title || "").toLowerCase()
          const kind = (place.kind || place.type || "").toLowerCase()
          return name.includes(query) || kind.includes(query)
        })
      : this.placesValue
    this.#renderMarkers(filtered)
  }

  #handleOutsideClick = (event) => {
    if (!this.hasPopupTarget) return
    if (this.popupTarget.contains(event.target)) return
    if (this.hasSearchTarget && this.searchTarget.contains(event.target)) return
    this.popupTarget.style.display = "none"
  }
}