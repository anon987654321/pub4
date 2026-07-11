// stimulus-textarea-autogrow@4.1.0 downloaded from https://unpkg.com/stimulus-textarea-autogrow@4.1.0/dist/stimulus-textarea-autogrow.mjs

import { Controller as n } from "@hotwired/stimulus";
function r(t, e) {
  let i;
  return (...o) => {
    const s = this;
    clearTimeout(i), i = setTimeout(() => t.apply(s, o), e);
  };
}
class l extends n {
  initialize() {
    this.autogrow = this.autogrow.bind(this);
  }
  connect() {
    this.element.style.overflow = "hidden";
    const e = this.resizeDebounceDelayValue;
    this.onResize = e > 0 ? r(this.autogrow, e) : this.autogrow, this.autogrow(), this.element.addEventListener("input", this.autogrow), window.addEventListener("resize", this.onResize);
  }
  disconnect() {
    window.removeEventListener("resize", this.onResize);
  }
  autogrow() {
    this.element.style.height = "auto", this.element.style.height = `${this.element.scrollHeight}px`;
  }
}
l.values = {
  resizeDebounceDelay: {
    type: Number,
    default: 100
  }
};
export {
  l as default
};
