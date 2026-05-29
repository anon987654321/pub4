import { Controller } from "@hotwired/stimulus"

/**
 * Futurism-style infinite scroll for Pagy lists.
 * Amazon-like "load more as you scroll" behavior.
 *
 * Usage on sentinel:
 *   <div data-controller="futurism-load-more"
 *        data-futurism-load-more-url-value="...next page url...">
 *     Loading more...
 *   </div>
 */
export default class extends Controller {
  static values = { url: String }

  observer = null
  loading = false

  connect() {
    if (!this.hasUrlValue) return

    this.observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting && !this.loading) {
          this.loadMore()
        }
      })
    }, { rootMargin: "200px" })

    this.observer.observe(this.element)
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  async loadMore() {
    if (this.loading || !this.urlValue) return
    this.loading = true
    this.element.textContent = "Loading more deals…"

    try {
      const response = await fetch(this.urlValue, {
        headers: { "Accept": "text/html" }
      })

      if (!response.ok) throw new Error("Failed to load more")

      const html = await response.text()
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, "text/html")

      // Find the next page's cards and append them
      const newGrid = doc.querySelector("#marketplace-listings")
      const currentGrid = document.querySelector("#marketplace-listings")

      if (newGrid && currentGrid) {
        Array.from(newGrid.children).forEach(child => {
          currentGrid.appendChild(child.cloneNode(true))
        })
      }

      // Update sentinel with next page URL if available
      const nextSentinel = doc.querySelector("[data-controller*='futurism-load-more']")
      if (nextSentinel && nextSentinel.dataset.futurismLoadMoreUrlValue) {
        this.urlValue = nextSentinel.dataset.futurismLoadMoreUrlValue
        this.loading = false
      } else {
        // No more pages
        this.element.remove()
      }
    } catch (error) {
      console.error("[futurism-load-more]", error)
      this.element.textContent = "Failed to load more. Scroll to retry."
      this.loading = false
    }
  }
}
