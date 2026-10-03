// @stimulus-components/rails-nested-form@5.0.0 downloaded from https://unpkg.com/@stimulus-components/rails-nested-form@5.0.0/dist/stimulus-rails-nested-form.mjs

import { Controller } from "@hotwired/stimulus";
const _RailsNestedForm = class _RailsNestedForm extends Controller {
  add(e) {
    e.preventDefault();
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, (/* @__PURE__ */ new Date()).getTime().toString());
    this.targetTarget.insertAdjacentHTML("beforebegin", content);
    const event = new CustomEvent("rails-nested-form:add", { bubbles: !0 });
    this.element.dispatchEvent(event);
  }
  remove(e) {
    e.preventDefault();
    const wrapper = e.target.closest(this.wrapperSelectorValue);
    if (wrapper.dataset.newRecord === "true")
      wrapper.remove();
    else {
      wrapper.style.display = "none";
      const input = wrapper.querySelector("input[name*='_destroy']");
      input.value = "1";
    }
    const event = new CustomEvent("rails-nested-form:remove", { bubbles: !0 });
    this.element.dispatchEvent(event);
  }
};
_RailsNestedForm.targets = ["target", "template"], _RailsNestedForm.values = {
  wrapperSelector: {
    type: String,
    default: ".nested-form-wrapper"
  }
};
let RailsNestedForm = _RailsNestedForm;
export {
  RailsNestedForm as default
};
