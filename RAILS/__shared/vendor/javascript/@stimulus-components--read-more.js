// @stimulus-components/read-more@5.0.0 downloaded from https://unpkg.com/@stimulus-components/read-more@5.0.0/dist/stimulus-read-more.mjs

import { Controller } from "@hotwired/stimulus";
const _ReadMore = class _ReadMore extends Controller {
  connect() {
    this.open = !1;
  }
  toggle(event) {
    this.open === !1 ? this.show(event) : this.hide(event);
  }
  show(event) {
    this.open = !0;
    const target = event.target;
    target.innerHTML = this.lessTextValue, this.contentTarget.style.setProperty("--read-more-line-clamp", "'unset'");
  }
  hide(event) {
    this.open = !1;
    const target = event.target;
    target.innerHTML = this.moreTextValue, this.contentTarget.style.removeProperty("--read-more-line-clamp");
  }
};
_ReadMore.targets = ["content"], _ReadMore.values = {
  moreText: String,
  lessText: String
};
let ReadMore = _ReadMore;
export {
  ReadMore as default
};
