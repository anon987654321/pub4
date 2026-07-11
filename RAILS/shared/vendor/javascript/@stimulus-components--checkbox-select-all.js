// @stimulus-components/checkbox-select-all@6.1.0 downloaded from https://unpkg.com/@stimulus-components/checkbox-select-all@6.1.0/dist/stimulus-checkbox-select-all.mjs

import { Controller } from "@hotwired/stimulus";
const _CheckboxSelectAll = class _CheckboxSelectAll extends Controller {
  initialize() {
    this.toggle = this.toggle.bind(this), this.refresh = this.refresh.bind(this);
  }
  checkboxAllTargetConnected(checkbox) {
    checkbox.addEventListener("change", this.toggle), this.refresh();
  }
  checkboxTargetConnected(checkbox) {
    checkbox.addEventListener("change", this.refresh), this.refresh();
  }
  checkboxAllTargetDisconnected(checkbox) {
    checkbox.removeEventListener("change", this.toggle), this.refresh();
  }
  checkboxTargetDisconnected(checkbox) {
    checkbox.removeEventListener("change", this.refresh), this.refresh();
  }
  toggle(e) {
    e.preventDefault(), this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = e.target.checked, this.triggerInputEvent(checkbox);
    });
  }
  refresh() {
    const checkboxesCount = this.checkboxTargets.length, checkboxesCheckedCount = this.checked.length;
    this.disableIndeterminateValue ? this.checkboxAllTarget.checked = checkboxesCheckedCount === checkboxesCount : (this.checkboxAllTarget.checked = checkboxesCheckedCount > 0, this.checkboxAllTarget.indeterminate = checkboxesCheckedCount > 0 && checkboxesCheckedCount < checkboxesCount);
  }
  triggerInputEvent(checkbox) {
    const event = new Event("input", { bubbles: !1, cancelable: !0 });
    checkbox.dispatchEvent(event);
  }
  get checked() {
    return this.checkboxTargets.filter((checkbox) => checkbox.checked);
  }
  get unchecked() {
    return this.checkboxTargets.filter((checkbox) => !checkbox.checked);
  }
};
_CheckboxSelectAll.targets = ["checkboxAll", "checkbox"], _CheckboxSelectAll.values = {
  disableIndeterminate: {
    type: Boolean,
    default: !1
  }
};
let CheckboxSelectAll = _CheckboxSelectAll;
export {
  CheckboxSelectAll as default
};
