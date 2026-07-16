import CharacterCounter from "@stimulus-components/character-counter"

// The upstream countdown mode assumes the controlled input has maxlength.
// Fall back to a conventional count when a product field intentionally has no
// hard limit, instead of displaying zero and logging an error to the console.
export default class extends CharacterCounter {
  get count() {
    const length = this.inputTarget.value.length

    if (this.hasCountdownValue && this.maxLength >= 0) {
      return Math.max(this.maxLength - length, 0)
    }

    return length
  }
}
