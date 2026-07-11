// @stimulus-components/popover@7.0.0 downloaded from https://unpkg.com/@stimulus-components/popover@7.0.0/dist/stimulus-popover.mjs

import { Controller } from "@hotwired/stimulus";
const _Popover = class _Popover extends Controller {
  async show(event) {
    const element = event.currentTarget;
    let content = null;
    if (this.hasContentTarget ? content = this.contentTarget.innerHTML : content = await this.fetch(), !content)
      return;
    const fragment = document.createRange().createContextualFragment(content);
    element.appendChild(fragment);
  }
  hide() {
    this.hasCardTarget && this.cardTarget.remove();
  }
  async fetch() {
    if (!this.remoteContent) {
      if (!this.hasUrlValue) {
        console.error("[stimulus-popover] You need to pass an url to fetch the popover content.");
        return;
      }
      const response = await fetch(this.urlValue);
      this.remoteContent = await response.text();
    }
    return this.remoteContent;
  }
};
_Popover.targets = ["card", "content"], _Popover.values = {
  url: String
};
let Popover = _Popover;
export {
  Popover as default
};
