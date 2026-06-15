import { Controller } from "@hotwired/stimulus"

// Debounced search-as-you-type for Turbo Frames and JSON endpoints.
export default class extends Controller {
  static targets = ["input", "frame", "results", "loading", "count"]
  static values = {
    url: String,
    delay: { type: Number, default: 300 },
    minLength: { type: Number, default: 0 },
  }

  connect() {
    this.timeout = null
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  input() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.perform(), this.delayValue)
  }

  async perform() {
    const query = this.hasInputTarget ? this.inputTarget.value.trim() : ""
    if (query.length > 0 && query.length < this.minLengthValue) return

    this.showLoading()

    if (this.hasFrameTarget) {
      const url = this.buildUrl(query)
      this.frameTarget.src = url
      return
    }

    if (!this.urlValue) return

    try {
      const response = await fetch(this.buildUrl(query), {
        headers: { Accept: "application/json", "X-Requested-With": "XMLHttpRequest" },
      })
      if (!response.ok) return
      const data = await response.json()
      this.renderJson(data)
    } catch (_error) {
      // network errors are ignored; user can retry
    } finally {
      this.hideLoading()
    }
  }

  buildUrl(query) {
    const url = new URL(this.urlValue, window.location.origin)
    if (query) url.searchParams.set("q", query)
    else url.searchParams.delete("q")
    return url.toString()
  }

  renderJson(data) {
    if (!this.hasResultsTarget) return

    const items = Array.isArray(data) ? data : data.results || []
    if (items.length === 0) {
      this.resultsTarget.innerHTML = '<p class="dim">No results</p>'
    } else {
      this.resultsTarget.innerHTML = items.map((item) => this.renderItem(item)).join("")
    }

    if (this.hasCountTarget && data.count !== undefined) {
      this.countTarget.textContent = `${data.count} result${data.count === 1 ? "" : "s"}`
    }
  }

  renderItem(item) {
    const label = item.name || item.title || item.label || "Result"
    const meta = [item.kind, item.city, item.artist].filter(Boolean).join(" · ")
    const href = item.url || (item.id ? `#${item.id}` : "#")
    return `<a href="${href}" class="search-hit"><strong>${label}</strong>${meta ? `<span class="dim"> · ${meta}</span>` : ""}</a>`
  }

  showLoading() {
    if (this.hasLoadingTarget) this.loadingTarget.hidden = false
  }

  hideLoading() {
    if (this.hasLoadingTarget) this.loadingTarget.hidden = true
  }

  frameTargetConnected() {
    this.hideLoading()
  }
}