// The maps page's points beyond the canvas: the list of links a keyboard or a
// screen reader reaches (the canvas's circles have no focus target), and the
// request for the points inside a new view as the reader pans.

// One <li> per point: a link when the point has a safe address, else its name.
export function renderPointList(list, count, points, { href, untitled }) {
  const items = points.map((point) => {
    const item = document.createElement("li")
    const url = href(point.url)
    const entry = document.createElement(url ? "a" : "span")
    if (url) entry.href = url
    const subtitle = point.subtitle ? ` · ${point.subtitle}` : ""
    entry.textContent = `${point.title || untitled}${subtitle}`
    item.append(entry)
    return item
  })
  list.replaceChildren(...items)
  if (count) count.textContent = `(${points.length})`
}

// The points inside bounds (MapLibre's LngLatBounds, or anything with the same
// four getters), from Maps::HomeController#index as JSON; null on any failure.
export async function fetchViewPoints(pointsUrl, bounds, signal) {
  const url = new URL(pointsUrl, window.location.origin)
  url.search = new URLSearchParams({
    sw_lat: bounds.getSouth(), sw_lng: bounds.getWest(), ne_lat: bounds.getNorth(), ne_lng: bounds.getEast()
  }).toString()
  const response = await fetch(url, { headers: { Accept: "application/json" }, signal })
  if (!response.ok) return null

  const points = await response.json()
  return Array.isArray(points) ? points : null
}

// Asks for the points in a new view a moment after the map settles, so a drag
// is one request rather than dozens, and drops an answer a newer one replaced.
export class ViewPoints {
  constructor(url, onPoints) {
    this.url = url
    this.onPoints = onPoints
  }

  schedule(bounds) {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.refetch(bounds), 300)
  }

  async refetch(bounds) {
    this.request?.abort()
    this.request = new AbortController()
    try {
      const points = await fetchViewPoints(this.url, bounds, this.request.signal)
      if (points) this.onPoints(points)
    } catch (error) {
      if (error.name !== "AbortError") console.error("Brgen map points could not be refetched.", error)
    }
  }

  stop() {
    clearTimeout(this.timer)
    this.request?.abort()
  }
}
