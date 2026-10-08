// @stimulus-components/password-visibility@3.0.0 downloaded from https://unpkg.com/@stimulus-components/password-visibility@3.0.0/dist/stimulus-password-visibility.mjs

import { Controller } from "@hotwired/stimulus";
const _PasswordVisibility = class _PasswordVisibility extends Controller {
  connect() {
    this.hidden = this.inputTarget.type === "password", this.class = this.hasHiddenClass ? this.hiddenClass : "hidden";
  }
  toggle(e) {
    e.preventDefault(), this.inputTarget.type = this.hidden ? "text" : "password", this.hidden = !this.hidden, this.iconTargets.forEach((icon) => icon.classList.toggle(this.class));
  }
};
_PasswordVisibility.targets = ["input", "icon"], _PasswordVisibility.classes = ["hidden"];
let PasswordVisibility = _PasswordVisibility;
export {
  PasswordVisibility as default
};
