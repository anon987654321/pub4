// @stimulus-components/scroll-to@5.0.1 downloaded from https://unpkg.com/@stimulus-components/scroll-to@5.0.1/dist/stimulus-scroll-to.mjs

import { Controller } from "@hotwired/stimulus";
const _ScrollTo = class _ScrollTo extends Controller {
  initialize() {
    this.scroll = this.scroll.bind(this);
  }
  connect() {
    this.element.addEventListener("click", this.scroll);
  }
  disconnect() {
    this.element.removeEventListener("click", this.scroll);
  }
  scroll(event) {
    event.preventDefault();
    const id = this.element.hash.replace(/^#/, ""), target = document.getElementById(id);
    if (!target) {
      console.warn(`[stimulus-scroll-to] The element with the id: "${id}" does not exist on the page.`);
      return;
    }
    const offsetPosition = target.getBoundingClientRect().top + window.pageYOffset - this.offset;
    window.scrollTo({
      top: offsetPosition,
      behavior: this.behavior
    });
  }
  get offset() {
    return this.hasOffsetValue ? this.offsetValue : this.defaultOptions.offset !== void 0 ? this.defaultOptions.offset : 10;
  }
  get behavior() {
    return this.behaviorValue || this.defaultOptions.behavior || "smooth";
  }
  get defaultOptions() {
    return {};
  }
};
_ScrollTo.values = {
  offset: Number,
  behavior: String
};
let ScrollTo = _ScrollTo;
export {
  ScrollTo as default
};
