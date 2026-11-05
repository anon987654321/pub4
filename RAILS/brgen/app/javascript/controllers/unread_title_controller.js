import { Controller } from "@hotwired/stimulus"

// Prefixes the tab title with the reader's unread DM count, "(3) Brgen", on
// every page. It sits on the tab bar's copy of the Messenger badge, which
// InboxBroadcastJob replaces whenever the count moves, so a new element
// connects with the new count. The tab bar is data-turbo-permanent, so a
// navigation keeps this element while the new page brings its own <title>;
// turbo:load puts the prefix back on it.
const PREFIX = /^\(\d+\+?\) /

export default class extends Controller {
  static values = { count: Number }

  connect() {
    this.apply = this.apply.bind(this)
    document.addEventListener("turbo:load", this.apply)
    this.apply()
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.apply)
  }

  apply() {
    const bare = document.title.replace(PREFIX, "")
    const n = this.countValue
    document.title = n > 0 ? `(${n > 99 ? "99+" : n}) ${bare}` : bare
  }
}
