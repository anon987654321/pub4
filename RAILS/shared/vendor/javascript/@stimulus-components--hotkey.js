// @stimulus-components/hotkey@1.0.0 downloaded from https://unpkg.com/@stimulus-components/hotkey@1.0.0/dist/stimulus-hotkey.mjs

import { Controller } from "@hotwired/stimulus";
class Hotkey extends Controller {
  click(event) {
    this.isClickable && !this.shouldIgnore(event) && (event.preventDefault(), this.element.click());
  }
  focus(event) {
    this.isClickable && !this.shouldIgnore(event) && (event.preventDefault(), this.element.focus());
  }
  shouldIgnore(event) {
    const target = event.target;
    return event.defaultPrevented || !!target?.closest("input, textarea, lexxy-editor");
  }
  get isClickable() {
    return getComputedStyle(this.element).pointerEvents !== "none";
  }
}
export {
  Hotkey as default
};
