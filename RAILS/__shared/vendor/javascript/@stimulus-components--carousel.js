import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values={options:Object}
  connect(){this.options=this.optionsValue||{};this.element.style.scrollSnapType=this.options.scrollSnapType||"x mandatory";this.element.style.overflowX=this.options.overflowX||"auto";this.element.dataset.stimulusCarouselReady="true"}
  disconnect(){this.element.style.removeProperty("scroll-snap-type");this.element.style.removeProperty("overflow-x");delete this.element.dataset.stimulusCarouselReady}
}
