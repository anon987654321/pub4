import { Controller } from "@hotwired/stimulus"

// Fetches what a thread said while this page was not listening.
//
// Live lines arrive over the conversation's cable stream, and a broadcast sent
// while the socket was down is gone: Action Cable does not replay. A phone that
// slept, a laptop that changed networks or a tab the browser froze came back to
// a log that silently stopped at the moment the connection did. So when the
// stream reconnects, the browser comes back online or the tab is shown again,
// this asks messages#index for every line after the newest one the log holds
// and adds them. The server renders them for this reader, in this request.
//
// Lines are matched by dom id: one that arrived by broadcast in the meantime is
// replaced with this copy rather than drawn twice. The log's own controller
// (conversation_log) stamps, groups and counts what this appends, as it does
// for a broadcast.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.busy = false
    this.onVisible = () => { if (document.visibilityState === "visible") this.catchUp() }
    this.onOnline = () => this.catchUp()
    document.addEventListener("visibilitychange", this.onVisible)
    window.addEventListener("online", this.onOnline)

    // Turbo marks <turbo-cable-stream-source> with `connected` while its
    // subscription is live. The first connect is the page loading, which has
    // nothing to catch up on; every later one is a reconnect.
    this.seenConnect = new WeakSet()
    this.sourceObserver = new MutationObserver((mutations) => {
      mutations.forEach(({ target }) => {
        if (target.localName !== "turbo-cable-stream-source" || !target.hasAttribute("connected")) return
        if (this.seenConnect.has(target)) this.catchUp()
        else this.seenConnect.add(target)
      })
    })
    this.sourceObserver.observe(document.body, { attributes: true, attributeFilter: ["connected"], subtree: true })
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisible)
    window.removeEventListener("online", this.onOnline)
    this.sourceObserver?.disconnect()
    this.sourceObserver = null
  }

  async catchUp() {
    const after = this.#newestId()
    if (!this.urlValue || !after || this.busy) return

    this.busy = true
    let more = false
    try {
      const url = new URL(this.urlValue, window.location.href)
      url.searchParams.set("after", String(after))
      const response = await fetch(url, { headers: { Accept: "text/html" }, credentials: "same-origin" })
      if (!response.ok || response.status === 204) return

      this.#merge(await response.text())
      // A long absence comes back a page at a time, from the last line added.
      more = response.headers.get("X-Catch-Up-More") === "1"
    } catch {
      // Still offline, or the server is: the next reconnect or visit asks again.
    } finally {
      this.busy = false
    }
    if (more) this.catchUp()
  }

  #merge(html) {
    const template = document.createElement("template")
    template.innerHTML = html
    Array.from(template.content.children).forEach((line) => {
      const existing = line.id ? this.element.querySelector(`:scope > [id="${line.id}"]`) : null
      if (existing) existing.replaceWith(line)
      else this.element.append(line)
    })
  }

  // The highest message id among the log's own lines. An optimistic placeholder
  // carries no id, and the history sentinel and day breaks are not messages.
  #newestId() {
    return Array.from(this.element.querySelectorAll(":scope > li[id^='message_']"))
      .map((line) => Number.parseInt(line.id.slice("message_".length), 10))
      .filter((id) => Number.isFinite(id))
      .reduce((newest, id) => Math.max(newest, id), 0)
  }
}
