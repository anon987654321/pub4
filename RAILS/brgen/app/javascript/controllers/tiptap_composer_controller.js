import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor", "input"]

  connect() {
    this.bootEditor()
  }

  async bootEditor() {
    if (!this.hasEditorTarget || !this.hasInputTarget) return

    const { Editor } = await import("https://esm.sh/@tiptap/core@2")
    const { StarterKit } = await import("https://esm.sh/@tiptap/starter-kit@2")

    this.editor = new Editor({
      element: this.editorTarget,
      extensions: [StarterKit],
      content: this.inputTarget.value || "",
      onUpdate: ({ editor }) => {
        this.inputTarget.value = editor.getText()
      }
    })
  }

  disconnect() {
    this.editor?.destroy()
  }
}
