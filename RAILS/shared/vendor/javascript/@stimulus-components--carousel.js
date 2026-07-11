// @stimulus-components/carousel@6.0.0 downloaded from https://unpkg.com/@stimulus-components/carousel@6.0.0/dist/stimulus-carousel.mjs

import { Controller } from "@hotwired/stimulus";
import Swiper from "swiper/bundle";
const _Carousel = class _Carousel extends Controller {
  connect() {
    this.swiper = new Swiper(this.element, {
      ...this.defaultOptions,
      ...this.optionsValue
    });
  }
  disconnect() {
    this.swiper.destroy(), this.swiper = void 0;
  }
  get defaultOptions() {
    return {};
  }
};
_Carousel.values = {
  options: Object
};
let Carousel = _Carousel;
export {
  Carousel as default
};
