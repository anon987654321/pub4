// @stimulus-components/sortable@5.0.3 downloaded from https://cdn.jsdelivr.net/npm/@stimulus-components/sortable@5.0.3/dist/stimulus-sortable.mjs

import { Controller } from "@hotwired/stimulus";
import Sortable from "sortablejs";
import { FetchRequest } from "@rails/request.js";
const _StimulusSortable = class _StimulusSortable extends Controller {
  initialize() {
    this.onUpdate = this.onUpdate.bind(this);
    this.onKeyboardReorder = this.onKeyboardReorder.bind(this);
  }

  async onKeyboardReorder(event) {
    if (event.target === this.element) return;
    if (event.key !== "ArrowUp" && event.key !== "ArrowDown") return;

    let item = event.target;
    while (item && item.parentElement !== this.element) item = item.parentElement;
    if (!item || item.parentElement !== this.element || event.target !== item) return;

    const items = Array.from(this.element.children);
    const index = items.indexOf(item);
    const nextIndex = event.key === "ArrowUp" ? index - 1 : index + 1;
    if (nextIndex < 0 || nextIndex >= items.length) return;

    event.preventDefault();
    const neighbor = items[nextIndex];
    if (event.key === "ArrowUp") {
      this.element.insertBefore(item, neighbor);
    } else {
      this.element.insertBefore(item, neighbor.nextSibling);
    }
    item.focus();

    const newIndex = Array.from(this.element.children).indexOf(item);
    await this.onUpdate({ item, newIndex });
  }
  connect() {
    this.sortable = new Sortable(this.element, {
      ...this.defaultOptions,
      ...this.options
    });
    this.element.addEventListener("keydown", this.onKeyboardReorder);
    Array.from(this.element.children).forEach((item) => {
      if (!item.hasAttribute("tabindex")) item.tabIndex = 0;
      item.setAttribute("aria-keyshortcuts", "ArrowUp ArrowDown");
    });
  }
  disconnect() {
    this.element.removeEventListener("keydown", this.onKeyboardReorder);
    this.sortable.destroy(), this.sortable = void 0;
  }
  async onUpdate({ item, newIndex }) {
    if (!item.dataset.sortableUpdateUrl) return;
    const param = this.resourceNameValue ? `${this.resourceNameValue}[${this.paramNameValue}]` : this.paramNameValue, data = new FormData();
    return data.append(param, newIndex + 1), await new FetchRequest(this.methodValue, item.dataset.sortableUpdateUrl, {
      body: data,
      responseKind: this.responseKindValue
    }).perform();
  }
  get options() {
    return {
      animation: this.animationValue || this.defaultOptions.animation || 150,
      handle: this.handleValue || this.defaultOptions.handle || void 0,
      onUpdate: this.onUpdate
    };
  }
  get defaultOptions() {
    return {};
  }
};
_StimulusSortable.values = {
  resourceName: String,
  paramName: {
    type: String,
    default: "position"
  },
  responseKind: {
    type: String,
    default: "html"
  },
  animation: Number,
  handle: String,
  method: {
    type: String,
    default: "patch"
  }
};
let StimulusSortable = _StimulusSortable;
export {
  StimulusSortable as default
};
