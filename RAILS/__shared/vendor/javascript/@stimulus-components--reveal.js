// @stimulus-components/reveal@5.0.0 downloaded from https://unpkg.com/@stimulus-components/reveal@5.0.0/dist/stimulus-reveal-controller.mjs

import { Controller } from "@hotwired/stimulus";
const _Reveal = class _Reveal extends Controller {
  connect() {
    this.class = this.hasHiddenClass ? this.hiddenClass : "hidden";
  }
  toggle() {
    this.itemTargets.forEach((item) => {
      item.classList.toggle(this.class);
    });
  }
  show() {
    this.itemTargets.forEach((item) => {
      item.classList.remove(this.class);
    });
  }
  hide() {
    this.itemTargets.forEach((item) => {
      item.classList.add(this.class);
    });
  }
};
_Reveal.targets = ["item"], _Reveal.classes = ["hidden"];
let Reveal = _Reveal;
export {
  Reveal as default
};
