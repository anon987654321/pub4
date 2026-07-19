// MASTER visual governor: state-aware animation pressure control before mask.js loads.
// Limits sourced from data/ops/visual.yml (SINGULARITY / ONE_SOURCE). Do not duplicate.
(() => {
  const maxFps = 24;
  const maxParticles = 200;
  const reducedMotionParticles = 64;
  const minFrameMs = 1000 / maxFps;
  const nativeRaf = window.requestAnimationFrame.bind(window);
  const nativePush = Array.prototype.push;
  let last = 0;
  let hiddenWaiters = [];

  function frozen() {
    // Visuals freeze only on an explicit visualRuntime=frozen signal — NOT on
    // masterState=fail. A backend "fail" (TTS/replicate/health) must not black
    // out the face; it renders through the fault and reacts to it instead.
    return document.body?.dataset.visualRuntime === "frozen";
  }

  function particleLike(value) {
    return value &&
      typeof value === "object" &&
      typeof value.vx === "number" &&
      typeof value.vy === "number" &&
      typeof value.vz === "number" &&
      typeof value.index === "number" &&
      typeof value.group === "string";
  }

  Array.prototype.push = function(...items) {
    if (items.some(particleLike) && this.length >= maxParticles) return this.length;
    return nativePush.apply(this, items);
  };

  window.MASTER_VISUAL_LIMITS = Object.freeze({
    maxFps,
    maxParticles,
    reducedMotionParticles,
    pauseWhenHidden: true,
    freezeOnFail: false
  });

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) return;
    const waiters = hiddenWaiters;
    hiddenWaiters = [];
    waiters.forEach((callback) => window.requestAnimationFrame(callback));
  }, { passive: true });

  window.requestAnimationFrame = (callback) => {
    if (document.hidden || frozen()) {
      hiddenWaiters.push(callback);
      return hiddenWaiters.length;
    }

    return nativeRaf((now) => {
      if (now - last < minFrameMs) {
        return window.requestAnimationFrame(callback);
      }
      last = now;
      callback(now);
    });
  };
})();
