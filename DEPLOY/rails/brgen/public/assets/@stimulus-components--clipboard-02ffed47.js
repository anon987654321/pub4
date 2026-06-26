// @stimulus-components/clipboard@5.0.0 downloaded from https://cdn.jsdelivr.net/npm/@stimulus-components/clipboard@5.0.0/dist/stimulus-clipboard.mjs

import { Controller } from "@hotwired/stimulus";
const _Clipboard = class _Clipboard extends Controller {
  connect() {
    this.hasButtonTarget && (this.originalContent = this.buttonTarget.innerHTML);
  }
  copy(event) {
    event.preventDefault();
    const text = this.sourceTarget.innerHTML || this.sourceTarget.value;
    navigator.clipboard.writeText(text).then(() => this.copied());
  }
  copied() {
    this.hasButtonTarget && (this.timeout && clearTimeout(this.timeout), this.buttonTarget.innerHTML = this.successContentValue, this.timeout = setTimeout(() => {
      this.buttonTarget.innerHTML = this.originalContent;
    }, this.successDurationValue));
  }
};
_Clipboard.targets = ["button", "source"], _Clipboard.values = {
  successContent: String,
  successDuration: {
    type: Number,
    default: 2e3
  }
};
let Clipboard = _Clipboard;
export {
  Clipboard as default
};
