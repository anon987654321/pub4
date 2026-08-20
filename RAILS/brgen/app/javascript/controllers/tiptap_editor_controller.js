import { Controller } from "@hotwired/stimulus"

// Progressive-enhancement rich-text editor for the compose box. Mounts a minimal
// Tiptap editor over the plain textarea (which stays the submitted field and the
// fallback). If Tiptap fails to load, the textarea is untouched and fully works.
export default class extends Controller {
  static targets = ["field", "mount", "toolbar"]

  // Mount on first interaction, not on connect.
  //
  // This controller lives on .composer-body inside the compose <dialog>, which
  // is closed on page load. Stimulus connects controllers inside a closed dialog
  // all the same, so connect() used to fetch @tiptap/core and
  // @tiptap/starter-kit from esm.sh -- and with them the whole ProseMirror tree,
  // dozens of module requests -- on every front-page visit, for an editor nobody
  // had asked for. Measured 537 requests for one brgen front-page load, four of
  // them still unresolved 20 seconds in.
  //
  // The textarea is the submitted field and the working fallback either way (see
  // the class comment), so deferring costs nothing: by the time anyone can type
  // rich text they have focused the box, and mount() has run.
  connect() {
    if (!this.hasFieldTarget || !this.hasMountTarget) return

    this.mount = this.mount.bind(this)
    this.flush = this.flush.bind(this)
    // focusin bubbles (focus does not), so one listener on the root covers the
    // textarea and the toolbar buttons.
    this.element.addEventListener("focusin", this.mount, { once: true })
    this.element.addEventListener("pointerdown", this.mount, { once: true })
    // Capture: copy the editor into the textarea before form-submit validates.
    this.form = this.element.closest("form")
    this.form?.addEventListener("submit", this.flush, true)
  }

  async mount() {
    if (this.mounted) return
    this.mounted = true
    this.element.removeEventListener("focusin", this.mount)
    this.element.removeEventListener("pointerdown", this.mount)

    try {
      const { Editor } = await import("@tiptap/core")
      const { default: StarterKit } = await import("@tiptap/starter-kit")

      this.editor = new Editor({
        element: this.mountTarget,
        extensions: [
          StarterKit.configure({
            heading: false,
            codeBlock: false,
            horizontalRule: false,
            blockquote: false
          })
        ],
        content: this.fieldTarget.value,
        // Carry the textarea's placeholder across. Tiptap replaces the field
        // with a contenteditable, which has no placeholder of its own, so
        // taking over silently blanked the compose prompt and the box read as
        // an empty rectangle. _tiptap.scss paints this via ::before.
        editorProps: {
          attributes: {
            class: "tiptap_area",
            "aria-label": this.fieldTarget.getAttribute("placeholder") || "Compose",
            "data-placeholder": this.fieldTarget.getAttribute("placeholder") || ""
          }
        },
        onUpdate: ({ editor }) => this._sync(editor)
      })

      // Tiptap is live: hide the raw textarea, reveal editor + toolbar.
      this.fieldTarget.classList.add("visually-hidden")
      this.fieldTarget.setAttribute("aria-hidden", "true")
      this.fieldTarget.tabIndex = -1
      this.mountTarget.hidden = false
      if (this.hasToolbarTarget) this.toolbarTarget.hidden = false
      // Mounting is triggered by the user focusing the textarea, and the line
      // above just hid the element they focused. Carry the caret into the editor
      // or the next keystroke goes to a visually-hidden field.
      this.editor.commands.focus("end")
    } catch (err) {
      // esm.sh/import failed — leave the plain textarea in place. Deliberately
      // not retried: the textarea is fully functional, and re-requesting a CDN
      // on every focus is worse than staying plain for the rest of the visit.
      if (window.MASTER_LOG?.warn) window.MASTER_LOG.warn("tiptap_editor", err)
    }
  }

  disconnect() {
    this.element.removeEventListener("focusin", this.mount)
    this.element.removeEventListener("pointerdown", this.mount)
    this.form?.removeEventListener("submit", this.flush, true)
    if (this.editor) { this.editor.destroy(); this.editor = null }
  }

  flush() {
    if (this.editor) this._sync(this.editor)
  }

  _sync(editor) {
    const html = editor.isEmpty ? "" : editor.getHTML()
    this.fieldTarget.value = html
    // Let feed-compose (title sync) and autogrow react as if typed.
    this.fieldTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  bold(e) { e.preventDefault(); this.editor?.chain().focus().toggleBold().run() }
  italic(e) { e.preventDefault(); this.editor?.chain().focus().toggleItalic().run() }
  bulletList(e) { e.preventDefault(); this.editor?.chain().focus().toggleBulletList().run() }
}
