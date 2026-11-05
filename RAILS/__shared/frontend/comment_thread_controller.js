import { Controller } from "@hotwired/stimulus"

// One comment in a thread (comments/_comment).
//
// Collapse: the toggle is rendered hidden and shown here, so it exists only
// where it works. It hides the comment's body, reply box and replies, and its
// label and a polite status say how many replies went out of view.
//
// Reply: opening the Reply disclosure puts the caret in its editor. Focusing
// the textarea is what mounts Tiptap (tiptap_editor_controller), which then
// carries the caret into the editor it mounted.
export default class extends Controller {
  static targets = ["toggle", "part", "replies", "status"]
  static values = {
    collapse: String,
    expandNone: String,
    expandOne: String,
    expandOther: String,
    hiddenOne: String,
    hiddenOther: String,
  }

  connect() {
    if (this.hasToggleTarget) this.toggleTarget.hidden = false
  }

  toggle() {
    const collapsing = this.toggleTarget.getAttribute("aria-expanded") === "true"
    this.partTargets.forEach((part) => { part.hidden = collapsing })
    this.toggleTarget.setAttribute("aria-expanded", String(!collapsing))
    const count = this.hiddenReplyCount()
    this.toggleTarget.textContent = collapsing ? this.expandLabel(count) : this.collapseValue
    if (this.hasStatusTarget) this.statusTarget.textContent = collapsing && count > 0 ? this.hiddenLabel(count) : ""
  }

  focusReply(event) {
    const disclosure = event.currentTarget
    if (!disclosure.open) return

    const field = disclosure.querySelector(".tiptap_area[contenteditable=true]") || disclosure.querySelector("textarea")
    field?.focus()
  }

  // Every comment under this one, at any depth.
  hiddenReplyCount() {
    return this.hasRepliesTarget ? this.repliesTarget.querySelectorAll("article.comment").length : 0
  }

  expandLabel(count) {
    if (count === 0) return this.expandNoneValue
    return (count === 1 ? this.expandOneValue : this.expandOtherValue).replace("%{count}", count)
  }

  hiddenLabel(count) {
    return (count === 1 ? this.hiddenOneValue : this.hiddenOtherValue).replace("%{count}", count)
  }
}
