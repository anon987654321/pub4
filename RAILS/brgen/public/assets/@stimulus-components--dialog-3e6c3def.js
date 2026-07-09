// @stimulus-components/dialog@1.0.1 downloaded from https://unpkg.com/@stimulus-components/dialog@1.0.1/dist/stimulus-dialog.mjs

import { Controller } from "@hotwired/stimulus";
const _Dialog = class _Dialog extends Controller {
  initialize() {
    this.forceClose = this.forceClose.bind(this);
  }
  connect() {
    this.openValue && this.open(), document.addEventListener("turbo:before-render", this.forceClose);
  }
  disconnect() {
    document.removeEventListener("turbo:before-render", this.forceClose);
  }
  open() {
    this.dialogTarget.showModal();
  }
  close() {
    this.dialogTarget.setAttribute("closing", ""), Promise.all(this.dialogTarget.getAnimations().map((animation) => animation.finished)).then(() => {
      this.dialogTarget.removeAttribute("closing"), this.dialogTarget.close();
    });
  }
  backdropClose(event) {
    event.target === this.dialogTarget && this.close();
  }
  forceClose() {
    this.dialogTarget.close();
  }
};
_Dialog.targets = ["dialog"], _Dialog.values = {
  open: {
    type: Boolean,
    default: !1
  }
};
let Dialog = _Dialog;
export {
  Dialog as default
};
