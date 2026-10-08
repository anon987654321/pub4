import { Controller } from "@hotwired/stimulus";
import lightGallery from "lightgallery";
const _Lightbox = class _Lightbox extends Controller {
  connect() {
    this.lightGallery = lightGallery(this.element, {
      ...this.defaultOptions,
      ...this.optionsValue
    });
  }
  disconnect() {
    this.lightGallery.destroy();
  }
  get defaultOptions() {
    return {};
  }
};
_Lightbox.values = {
  options: Object
};
let Lightbox = _Lightbox;
export {
  Lightbox as default
};
