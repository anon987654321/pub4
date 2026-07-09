// @stimulus-components/character-counter@5.1.0 downloaded from https://cdn.jsdelivr.net/npm/@stimulus-components/character-counter@5.1.0/dist/stimulus-character-counter.mjs

import { Controller } from "@hotwired/stimulus";
const _CharacterCounter = class _CharacterCounter extends Controller {
  initialize() {
    this.update = this.update.bind(this);
  }
  connect() {
    this.update(), this.inputTarget.addEventListener("input", this.update);
  }
  disconnect() {
    this.inputTarget.removeEventListener("input", this.update);
  }
  update() {
    this.counterTarget.innerHTML = this.count.toLocaleString();
  }
  get count() {
    let value = this.inputTarget.value.length;
    return this.hasCountdownValue && (this.maxLength < 0 && console.error(
      `[stimulus-character-counter] You need to add a maxlength attribute on the input to use countdown mode. The current value is: ${this.maxLength}.`
    ), value = Math.max(this.maxLength - value, 0)), value;
  }
  get maxLength() {
    return this.inputTarget.maxLength;
  }
};
_CharacterCounter.targets = ["input", "counter"], _CharacterCounter.values = { countdown: Boolean };
let CharacterCounter = _CharacterCounter;
export {
  CharacterCounter as default
};
