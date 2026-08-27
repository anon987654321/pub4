import CharacterCounter from "@stimulus-components/character-counter"

// The upstream countdown mode assumes the controlled input has maxlength.
// Fall back to a conventional count when a product field intentionally has no
// hard limit, instead of displaying zero and logging an error to the console.
export default class extends CharacterCounter {
  get count() {
    const length = this._readableLength(this.inputTarget.value)

    if (this.hasCountdownValue && this.maxLength >= 0) {
      return Math.max(this.maxLength - length, 0)
    }

    return length
  }

  // The controlled field holds Tiptap's HTML wherever an editor is mounted on
  // it, so value.length counted "<p>" and "</strong>" against the writer: a
  // 500-character budget could read as spent at 460 typed characters, and the
  // countdown hit zero while the box still looked half empty. Count the text.
  _readableLength(raw) {
    if (!raw.includes("<")) return raw.length
    const doc = new DOMParser().parseFromString(raw, "text/html")
    return (doc.body.textContent || "").length
  }
}
