import { Controller } from "@hotwired/stimulus"
import { ViewPoints, renderPointList } from "controllers/map_points"

const DEFAULT_STYLE = "https://tiles.openfreemap.org/styles/positron"
const POINT_SOURCE = "brgen-map-points"
const CLUSTER_LAYER = "brgen-map-point-clusters"
const CLUSTER_COUNT_LAYER = "brgen-map-point-cluster-count"
const POINT_LAYER = "brgen-map-unclustered-points"

export default class extends Controller {
  static targets = ["canvas", "search", "popup", "list", "listCount"]
  static values = {
    centerLat: Number,
    centerLng: Number,
    zoom: Number,
    styleUrl: String,
    points: Array,
    // Where the points for a new view come from (Maps::HomeController#index
    // as JSON, filtered by sw_lat/sw_lng/ne_lat/ne_lng).
    pointsUrl: { type: String, default: "" },
    // The popup and list words, from the page's locale.
    openLabel: { type: String, default: "Open" },
    pointLabel: { type: String, default: "Map point" },
    kindLabel: { type: String, default: "point" },
    emptyLabel: { type: String, default: "No map points yet." }
  }

  connect() {
    this.points = this.hasPointsValue ? this.pointsValue : this._readPoints()
    this.filteredPoints = this.points
    this.map = null
    this.mapLoaded = false
    this._boundSearch = this.filterPoints.bind(this)
    this._list(this.filteredPoints)
    this._watchViewPoints()
    this._boot()
  }

  disconnect() {
    this.viewPoints?.stop()
    this._destroy()
  }

  // The page embeds the points for the city's opening view only; as the reader
  // pans, the points inside the new view are asked for (controllers/map_points).
  _watchViewPoints() {
    if (!this.pointsUrlValue) return

    this.viewPoints = new ViewPoints(this.pointsUrlValue, (points) => {
      this.points = points
      this.filterPoints()
    })
  }

  _list(points) {
    if (!this.hasListTarget) return

    const count = this.hasListCountTarget ? this.listCountTarget : null
    const href = (url) => this._safeHref(url)
    renderPointList(this.listTarget, count, points, { href, untitled: this.pointLabelValue })
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
    } catch (error) {
      console.error("Brgen map points could not be read.", error)
      return []
    }
  }

  _hasCenter() {
    const latitude = this.element.getAttribute("data-map-center-lat-value")
    const longitude = this.element.getAttribute("data-map-center-lng-value")
    return latitude !== null && latitude.trim() !== "" &&
      longitude !== null && longitude.trim() !== "" &&
      Number.isFinite(this.centerLatValue) &&
      Number.isFinite(this.centerLngValue)
  }

  _center() {
    // Unknown cities open at a world view, never at Bergen by accident.
    return this._hasCenter() ? [this.centerLngValue, this.centerLatValue] : [0, 0]
  }

  _styleUrl() {
    return this.hasStyleUrlValue && this.styleUrlValue ? this.styleUrlValue : DEFAULT_STYLE
  }

  _boot() {
    const canvas = this._rootCanvas()
    if (this.hasSearchTarget) {
      this.searchTarget.addEventListener("input", this._boundSearch)
    }
    if (!canvas || !window.maplibregl) return this._fallback()

    try {
      window.maplibregl.accessToken = ""
      this.map = new window.maplibregl.Map({
        container: canvas,
        style: this._styleUrl(),
        center: this._center(),
        zoom: this.hasZoomValue ? this.zoomValue : (this._hasCenter() ? 12.2 : 1.5),
        pitch: 55,
        bearing: -14,
        antialias: true
      })

      this.map.addControl(new window.maplibregl.NavigationControl({ visualizePitch: true }), "bottom-right")
      this.map.addControl(new window.maplibregl.GeolocateControl({
        // City-scale pins do not need GNSS precision; high accuracy holds the
        // GPS radio (and the heading sensor below) open for the whole map
        // session, which is the heaviest thing a low-end phone does here.
        positionOptions: { enableHighAccuracy: false },
        trackUserLocation: true,
        showUserHeading: true
      }), "bottom-right")

      this.map.on("load", () => {
        this.mapLoaded = true
        this._render(this.filteredPoints)
        this.map.on("moveend", () => this.viewPoints?.schedule(this.map.getBounds()))
      })

    } catch (error) {
      console.error("Brgen map renderer unavailable; showing the place list.", error)
      if (this.map) this.map.remove()
      this.map = null
      this._fallback()
    }
  }

  _destroy() {
    if (this.hasSearchTarget) {
      this.searchTarget.removeEventListener("input", this._boundSearch)
    }

    if (this.map) {
      this.map.remove()
      this.map = null
    }

    this.mapLoaded = false
  }

  _render(list = this.points) {
    if (!this.map || !this.mapLoaded) return

    const data = this._featureCollection(list)
    const source = this.map.getSource(POINT_SOURCE)

    if (source) {
      source.setData(data)
      return
    }

    this.map.addSource(POINT_SOURCE, {
      type: "geojson",
      data,
      cluster: true,
      clusterRadius: 44,
      clusterMaxZoom: 14
    })

    this.map.addLayer({
      id: CLUSTER_LAYER,
      type: "circle",
      source: POINT_SOURCE,
      filter: ["has", "point_count"],
      paint: {
        "circle-color": this._token("--maps-accent"),
        "circle-radius": [
          "step", ["get", "point_count"],
          15, 10, 17, 50, 20, 100, 24
        ],
        "circle-stroke-color": this._token("--maps-bg"),
        "circle-stroke-width": 2
      }
    })

    this.map.addLayer({
      id: CLUSTER_COUNT_LAYER,
      type: "symbol",
      source: POINT_SOURCE,
      filter: ["has", "point_count"],
      layout: {
        "text-field": ["get", "point_count_abbreviated"],
        "text-size": 12
      },
      paint: {
        "text-color": this._token("--maps-bg")
      }
    })

    this.map.addLayer({
      id: POINT_LAYER,
      type: "circle",
      source: POINT_SOURCE,
      filter: ["!", ["has", "point_count"]],
      paint: {
        "circle-color": [
          "match", ["get", "type"],
          "courier", this._token("--color-success"),
          "food", this._token("--color-success"),
          "place", this._token("--color-info"),
          "resource", this._token("--color-info"),
          "story", this._token("--maps-ink"),
          this._token("--maps-accent")
        ],
        "circle-radius": ["match", ["get", "type"], "courier", 9, 7],
        "circle-stroke-color": this._token("--maps-bg"),
        "circle-stroke-width": 2
      }
    })

    this.map.on("click", CLUSTER_LAYER, event => this._expandCluster(event))
    this.map.on("click", POINT_LAYER, event => this._openPoint(event))
    this.map.on("mouseenter", CLUSTER_LAYER, () => this._setPointer(true))
    this.map.on("mouseleave", CLUSTER_LAYER, () => this._setPointer(false))
    this.map.on("mouseenter", POINT_LAYER, () => this._setPointer(true))
    this.map.on("mouseleave", POINT_LAYER, () => this._setPointer(false))
  }

  _featureCollection(points) {
    const features = points.filter(point => {
      const lat = Number(point?.lat)
      const lng = Number(point?.lng)
      return point?.lat !== null && point?.lat !== undefined &&
        point?.lng !== null && point?.lng !== undefined &&
        String(point.lat).trim() !== "" && String(point.lng).trim() !== "" &&
        Number.isFinite(lat) && Number.isFinite(lng) &&
        lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
    }).map(point => ({
      type: "Feature",
      properties: {
        type: String(point.type || "resource"),
        title: String(point.title || this.pointLabelValue),
        subtitle: String(point.subtitle || ""),
        url: this._safeHref(point.url) || ""
      },
      geometry: {
        type: "Point",
        coordinates: [Number(point.lng), Number(point.lat)]
      }
    }))

    return { type: "FeatureCollection", features }
  }

  _token(name) {
    const value = getComputedStyle(this.element).getPropertyValue(name).trim()
    return value || getComputedStyle(this.element).color
  }

  _expandCluster(event) {
    const feature = event.features?.[0]
    if (!feature) return

    const source = this.map.getSource(POINT_SOURCE)
    source.getClusterExpansionZoom(feature.properties.cluster_id).then(zoom => {
      this.map.easeTo({ center: feature.geometry.coordinates, zoom })
    }).catch(error => {
      console.error("Brgen map cluster expansion failed.", error)
    })
  }

  _openPoint(event) {
    const feature = event.features?.[0]
    if (!feature) return

    const coordinates = feature.geometry.coordinates.slice()
    while (Math.abs(event.lngLat.lng - coordinates[0]) > 180) {
      coordinates[0] += event.lngLat.lng > coordinates[0] ? 360 : -360
    }

    const content = document.createElement("div")
    content.className = "map-popup"

    const title = document.createElement("strong")
    title.textContent = feature.properties.title || this.pointLabelValue
    content.append(title)

    if (feature.properties.subtitle) {
      const subtitle = document.createElement("p")
      subtitle.textContent = feature.properties.subtitle
      content.append(subtitle)
    }

    const href = this._safeHref(feature.properties.url)
    if (href) {
      const link = document.createElement("a")
      link.href = href
      link.textContent = this.openLabelValue
      content.append(link)
    }

    new window.maplibregl.Popup({ offset: 20 })
      .setLngLat(coordinates)
      .setDOMContent(content)
      .addTo(this.map)
  }

  _safeHref(value) {
    if (!value) return null

    try {
      const url = new URL(String(value), window.location.origin)
      if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) return null

      const cityApex = window.location.hostname.replace(/^maps\./i, "")
      const sameCity = url.hostname === cityApex || url.hostname.endsWith(`.${cityApex}`)
      if (url.hostname !== window.location.hostname && !sameCity) return null

      return url.href
    } catch (_) {
      return null
    }
  }

  _setPointer(active) {
    if (this.map) this.map.getCanvas().style.cursor = active ? "pointer" : ""
  }

  filterPoints() {
    const q = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : ""
    this.filteredPoints = q ? this.points.filter(point => {
      const haystack = [point.title, point.subtitle, point.type, point.city, point.kind]
        .filter(Boolean)
        .join(" ")
        .toLowerCase()
      return haystack.includes(q)
    }) : this.points
    this._list(this.filteredPoints)

    if (this.mapLoaded) {
      this._render(this.filteredPoints)
    } else if (!this.map) {
      this._fallback(this.filteredPoints)
    }
  }

  _fallback(points = this.filteredPoints || this.points) {
    const canvas = this._rootCanvas()
    if (!canvas) return

    canvas.classList.add("map-fallback")
    const fragment = document.createDocumentFragment()

    points.forEach(point => {
      const item = document.createElement("a")
      const href = this._safeHref(point.url)
      if (href) item.href = href

      const label = document.createElement("span")
      label.textContent = point.subtitle || point.type || this.kindLabelValue
      const title = document.createElement("strong")
      title.textContent = point.title || this.pointLabelValue
      item.append(label, title)
      fragment.append(item)
    })

    if (points.length === 0) {
      const empty = document.createElement("p")
      empty.textContent = this.emptyLabelValue
      fragment.append(empty)
    }

    canvas.replaceChildren(fragment)
  }
}
