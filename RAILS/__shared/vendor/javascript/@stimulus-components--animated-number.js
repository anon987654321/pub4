// @stimulus-components/animated-number@5.0.0 downloaded from https://cdn.jsdelivr.net/npm/@stimulus-components/animated-number@5.0.0/dist/stimulus-animated-number.mjs

import { Controller } from "@hotwired/stimulus";
const _AnimatedNumber = class _AnimatedNumber extends Controller {
  connect() {
    this.lazyValue ? this.lazyAnimate() : this.animate();
  }
  animate() {
    let startTimestamp = null;
    const step = (timestamp) => {
      startTimestamp || (startTimestamp = timestamp);
      const elapsed = timestamp - startTimestamp, progress = Math.min(elapsed / this.durationValue, 1);
      this.element.innerHTML = Math.floor(progress * (this.endValue - this.startValue) + this.startValue).toString(), progress < 1 && window.requestAnimationFrame(step);
    };
    window.requestAnimationFrame(step);
  }
  lazyAnimate() {
    new IntersectionObserver((entries, observer2) => {
      entries.forEach((entry) => {
        entry.isIntersecting && (this.animate(), observer2.unobserve(entry.target));
      });
    }, this.lazyAnimateOptions).observe(this.element);
  }
  // eslint-disable-next-line
  get lazyAnimateOptions() {
    return {
      threshold: this.lazyThresholdValue,
      rootMargin: this.lazyRootMarginValue
    };
  }
};
_AnimatedNumber.values = {
  start: Number,
  end: Number,
  duration: Number,
  lazyThreshold: Number,
  lazyRootMargin: {
    type: String,
    default: "0px"
  },
  lazy: Boolean
};
let AnimatedNumber = _AnimatedNumber;
export {
  AnimatedNumber as default
};
