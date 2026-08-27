import { Controller } from "@hotwired/stimulus"

// Search, opened over the page instead of parked in a rail.
//
// brgen carried search twice — a link in the left nav and a field in the right
// widgets rail — and both rails were removed. A palette is what replaces them:
// it costs no permanent chrome, it is reachable from the keyboard without
// travelling to a corner, and it keeps the feed behind it so a search is
// something you do to the page rather than somewhere you go.
//
// The trigger is a real button, so this works with no keyboard and with no
// pointer. The shortcuts are an accelerator on top of it, never the only way in.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.onKey = this.handleKey.bind(this)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    this.release()
  }

  // "/" is the reader's shortcut and Cmd-K the operator's; both are ignored the
  // moment the caret is already in a field, or "/" would be unusable in every
  // compose box on the site.
  handleKey(event) {
    if (event.key === "Escape" && this.isOpen) return this.close()

    const meta = (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k"
    const slash = event.key === "/" && !event.metaKey && !event.ctrlKey && !event.altKey
    if (!meta && !slash) return
    if (!meta && this.typingInField(event.target)) return

    event.preventDefault()
    this.isOpen ? this.close() : this.open()
  }

  // tagName is guarded because the target is not always an element: a keydown
  // dispatched at the document has none, and reading it there threw inside the
  // handler -- which silently cost the whole shortcut, since an exception in a
  // listener stops the rest of it.
  typingInField(el) {
    if (!el || typeof el.tagName !== "string") return false
    if (el.isContentEditable) return true
    return ["input", "textarea", "select"].includes(el.tagName.toLowerCase())
  }

  get isOpen() {
    return this.element.classList.contains("open")
  }

  open() {
    if (this.isOpen) return

    // Where focus came from, so Escape can put it back. A palette that dismisses
    // to nowhere leaves a keyboard reader at the top of the document.
    this.returnFocus = document.activeElement
    this.element.classList.add("open")
    document.documentElement.classList.add("palette-open")
    // Queried, not a target: the field belongs to shared/live_search_form,
    // which is rendered by four other surfaces and should not grow a data
    // attribute for this one.
    const field = this.element.querySelector('input[type="search"]')
    if (field) {
      field.focus()
      field.select()
    }
  }

  close() {
    if (!this.isOpen) return

    this.element.classList.remove("open")
    this.release()
    if (this.returnFocus && this.returnFocus.focus) this.returnFocus.focus()
    this.returnFocus = null
  }

  release() {
    document.documentElement.classList.remove("palette-open")
  }

  // Only the backdrop dismisses. A click inside the panel is a click on the
  // search, and closing on it would eat the first tap on every result.
  // currentTarget, not this.element: the controller wraps the trigger as well
  // as the overlay, so comparing against the root would never match.
  backdrop(event) {
    if (event.target === event.currentTarget) this.close()
  }
}
