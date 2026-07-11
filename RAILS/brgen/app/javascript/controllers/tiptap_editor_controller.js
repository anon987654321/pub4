import { Controller } from "@hotwired/stimulus"

// Progressive-enhancement rich-text editor for the compose box. Mounts a minimal
// Tiptap editor over the plain textarea (which stays the submitted field and the
// fallback). If Tiptap fails to load, the textarea is untouched and fully works.
export default class extends Controller {
  static targets = ["field", "mount", "toolbar"]

  async connect() {
    if (!this.hasFieldTarget || !this.hasMountTarget) return
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
        editorProps: { attributes: { class: "tiptap_area", "aria-label": "Compose" } },
        onUpdate: ({ editor }) => this._sync(editor)
      })

      // Tiptap is live: hide the raw textarea, reveal editor + toolbar.
      this.fieldTarget.classList.add("visually-hidden")
      this.fieldTarget.setAttribute("aria-hidden", "true")
      this.fieldTarget.tabIndex = -1
      this.mountTarget.hidden = false
      if (this.hasToolbarTarget) this.toolbarTarget.hidden = false
    } catch (err) {
      // esm.sh/import failed — leave the plain textarea in place.
      if (window.MASTER_LOG?.warn) window.MASTER_LOG.warn("tiptap_editor", err)
    }
  }

  disconnect() {
    if (this.editor) { this.editor.destroy(); this.editor = null }
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
