// @stimulus-components/notification@3.0.0 downloaded from https://cdn.jsdelivr.net/npm/@stimulus-components/notification@3.0.0/dist/stimulus-notification.mjs

import { Controller } from "@hotwired/stimulus";
import { useTransition } from "stimulus-use";
const _Notification = class _Notification extends Controller {
  initialize() {
    this.hide = this.hide.bind(this);
  }
  connect() {
    useTransition(this), this.hiddenValue === !1 && this.show();
  }
  show() {
    this.enter(), this.timeout = setTimeout(this.hide, this.delayValue);
  }
  async hide() {
    this.timeout && clearTimeout(this.timeout), await this.leave(), this.element.remove();
  }
};
_Notification.values = {
  delay: {
    type: Number,
    default: 3e3
  },
  hidden: {
    type: Boolean,
    default: !1
  }
};
let Notification = _Notification;
export {
  Notification as default
};
