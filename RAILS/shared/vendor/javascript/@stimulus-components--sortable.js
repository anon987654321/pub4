// @stimulus-components/sortable@5.0.3 downloaded from https://cdn.jsdelivr.net/npm/@stimulus-components/sortable@5.0.3/dist/stimulus-sortable.mjs

import { Controller } from "@hotwired/stimulus";
import Sortable from "sortablejs";
import { FetchRequest } from "@rails/request.js";
const _StimulusSortable = class _StimulusSortable extends Controller {
  initialize() {
    this.onUpdate = this.onUpdate.bind(this);
    this.onKeyboardReorder = this.onKeyboardReorder.bind(this);
  }

  installKeyboardControls() {
    this.removeKeyboardControls();

    Array.from(this.element.children).forEach((item) => {
      if (!item.hasAttribute("tabindex")) item.tabIndex = 0;
      item.setAttribute("aria-keyshortcuts", "ArrowUp ArrowDown");
      const controls = document.createElement("span");
      controls.dataset.sortableKeyboardControl = "true";
      controls.className = "sortable-keyboard-controls";

      [
        ["move-up", this.moveUpLabelValue || "Move up", -1],
        ["move-down", this.moveDownLabelValue || "Move down", 1]
      ].forEach(([name, label, delta]) => {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "btn btn-ghost btn-sm";
        button.textContent = delta < 0 ? "↑" : "↓";
        button.setAttribute("aria-label", label);
        button.dataset.action = `${this.identifier}#moveBy`;
        button.dataset.sortableDelta = String(delta);
        controls.append(button);
      });

      item.append(controls);
    });
    this.refreshKeyboardControls();
  }

  refreshKeyboardControls() {
    const items = Array.from(this.element.children);
    items.forEach((item, index) => {
      const controls = item.querySelector("[data-sortable-keyboard-control]");
      if (!controls) return;
      controls.querySelectorAll("button").forEach((button) => {
        const delta = Number(button.dataset.sortableDelta);
        button.disabled = (delta < 0 && index === 0) || (delta > 0 && index === items.length - 1);
      });
    });
  }

  removeKeyboardControls() {
    this.element.querySelectorAll("[data-sortable-keyboard-control]").forEach((node) => node.remove());
  }

  async moveBy(event) {
    let item = event.currentTarget;
    while (item && item.parentElement !== this.element) item = item.parentElement;
    const delta = Number(event.currentTarget.dataset.sortableDelta);
    if (!item || item.parentElement !== this.element || !Number.isInteger(delta)) return;

    const items = Array.from(this.element.children);
    const index = items.indexOf(item);
    const nextIndex = index + delta;
    if (index < 0 || nextIndex < 0 || nextIndex >= items.length) return;

    const neighbor = items[nextIndex];
    if (delta < 0) {
      this.element.insertBefore(item, neighbor);
    } else {
      this.element.insertBefore(item, neighbor.nextSibling);
    }
    item.focus();

    await this.onUpdate({ item, newIndex: nextIndex });
    this.refreshKeyboardControls();
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
    this.installKeyboardControls();
  }
  disconnect() {
    this.element.removeEventListener("keydown", this.onKeyboardReorder);
    this.removeKeyboardControls();
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
  moveUpLabel: {
    type: String,
    default: "Move up"
  },
  moveDownLabel: {
    type: String,
    default: "Move down"
  },
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
