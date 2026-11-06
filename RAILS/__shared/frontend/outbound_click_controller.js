// Counts clicks on links that leave the site.
//
// Nothing in this fleet counted one, so every estimate of what partner marketing
// earns was arithmetic over an unmeasured number — and in a network dashboard
// "nobody clicks" and "attribution is broken" produce the same zero.
//
// sendBeacon, not fetch: the page is navigating away, and fetch is cancelled when
// it does. The beacon is queued by the browser and survives the unload. If it is
// unavailable the click is simply not counted — measurement must never delay or
// swallow the navigation the visitor asked for.
//
// The href stays the merchant URL. Pointing it at our own host would hide it from
// TradeDoubler's Link Converter script, which rewrites outbound anchors in the
// browser, and would take attribution to zero — measurement that destroys the
// thing it measures. See Shared::OutboundClicksController for the same reasoning
// on why this is not a redirect.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    merchant: String,
    surface: String,
    epi: String,
    endpoint: { type: String, default: "/outbound_clicks" }
  }

  // click, not mousedown: a click that never happened is not a click, and
  // middle-click/ctrl-click open a tab without one, which is fine — undercounting
  // is honest, inventing clicks is not.
  record() {
    const url = this.urlValue || this.element.getAttribute("href")
    if (!url || !navigator.sendBeacon) return

    const body = new FormData()
    body.append("url", url)
    if (this.merchantValue) body.append("merchant", this.merchantValue)
    if (this.surfaceValue) body.append("surface", this.surfaceValue)
    if (this.epiValue) body.append("epi", this.epiValue)

    try {
      navigator.sendBeacon(this.endpointValue, body)
    } catch {
      // Never let a counter break a link.
    }
  }
}
