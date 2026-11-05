import { Controller } from "@hotwired/stimulus"

// Reply without reloading the pane. Reply on a line sets the composer's
// parent_id and writes the "Replying to" line above the box, the same two
// things conversations/_composer renders for ?reply_to=, which stays the path
// when JavaScript is off, or when the composer is not on screen (an edit or a
// message request is standing in for it) and the link is simply followed.
// Sending replaces the composer with a fresh one, which clears both.
export default class extends Controller {
  static values = { label: String, cancel: String }

  start(event) {
    const form = this.element.querySelector("#new_message")
    if (!form) return

    event.preventDefault()
    const { id } = event.params
    const { name, excerpt } = this.#quote(event.target.closest("article"))
    this.#clear(form)

    const parent = document.createElement("input")
    parent.type = "hidden"
    parent.name = "message[parent_id]"
    parent.value = id
    parent.dataset.messageReplyParent = ""

    const line = document.createElement("p")
    line.className = "msg-reply-context"
    line.dataset.messageReplyLine = ""
    line.append(`${this.labelValue.replace("%{name}", name)}: ${excerpt} `)

    const cancel = document.createElement("button")
    cancel.type = "button"
    cancel.className = "button button-ghost button-small"
    cancel.textContent = this.cancelValue
    cancel.addEventListener("click", () => { this.#clear(form); this.#focus(form) })
    line.append(cancel)

    form.prepend(parent)
    form.prepend(line)
    event.target.closest("details")?.removeAttribute("open")
    this.#focus(form)
  }

  // Who wrote the line and how it starts, read from the line itself, the way
  // the server's copy is truncated to sixty characters.
  #quote(article) {
    const name = article?.querySelector(".msg-nick")?.textContent.trim() ?? ""
    const body = article?.querySelector(":scope > p:not([class])")?.textContent.trim() ?? ""
    return { name, excerpt: body.length > 60 ? `${body.slice(0, 57)}...` : body }
  }

  #clear(form) {
    form.querySelectorAll("[data-message-reply-parent], [data-message-reply-line]").forEach((node) => node.remove())
  }

  #focus(form) {
    form.querySelector("textarea")?.focus()
  }
}
