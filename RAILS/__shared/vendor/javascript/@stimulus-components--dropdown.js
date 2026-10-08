// @stimulus-components/dropdown@3.0.0 downloaded from https://cdn.jsdelivr.net/npm/@stimulus-components/dropdown@3.0.0/dist/stimulus-dropdown.mjs

import { Controller } from "@hotwired/stimulus";
import { useTransition } from "stimulus-use";
const _Dropdown = class _Dropdown extends Controller {
  connect() {
    useTransition(this, {
      element: this.menuTarget
    });
  }
  toggle() {
    this.toggleTransition();
  }
  hide(event) {
    !this.element.contains(event.target) && !this.menuTarget.classList.contains("hidden") && this.leave();
  }
};
_Dropdown.targets = ["menu"];
let Dropdown = _Dropdown;
export {
  Dropdown as default
};
