// Keyboard inset for the face prompt. Same remainder as RAILS
// viewport_aware_controller.js: env(keyboard-inset-height) is Chromium-only
// and stays 0 on iOS, where #zsh is position:fixed at the layout bottom.
(function () {
  "use strict";
  const KEYBOARD_MIN = 80;
  const vv = window.visualViewport;
  var frame = 0;

  function editing() {
    const el = document.activeElement;
    if (!el) return false;
    const tag = el.tagName;
    return tag === "INPUT" || tag === "TEXTAREA" || el.isContentEditable;
  }

  function apply() {
    var inset = 0;
    if (vv) {
      const remainder = window.innerHeight - vv.height - vv.offsetTop;
      if (remainder > KEYBOARD_MIN && editing()) inset = remainder;
    }
    document.documentElement.style.setProperty("--keyboard-inset", Math.round(inset) + "px");
  }

  function schedule() {
    if (frame) return;
    frame = requestAnimationFrame(function () {
      frame = 0;
      apply();
    });
  }

  if (vv) {
    vv.addEventListener("resize", schedule, { passive: true });
    vv.addEventListener("scroll", schedule, { passive: true });
  }
  window.addEventListener("focusout", schedule, { passive: true });
  apply();
})();
