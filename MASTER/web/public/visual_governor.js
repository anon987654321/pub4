// MASTER visual governor: cap animation pressure before mask.js loads.
(() => {
  const maxFps = 24;
  const maxParticles = 200;
  const minFrameMs = 1000 / maxFps;
  const nativeRaf = window.requestAnimationFrame.bind(window);
  const nativePush = Array.prototype.push;
  let last = 0;
  let hiddenWaiters = [];

  function particleLike(value) {
    return value &&
      typeof value === "object" &&
      typeof value.x === "number" &&
      typeof value.y === "number" &&
      typeof value.group === "string";
  }

  Array.prototype.push = function(...items) {
    if (this.length >= maxParticles && items.some(particleLike)) return this.length;
    return nativePush.apply(this, items);
  };

  window.MASTER_VISUAL_LIMITS = Object.freeze({
    maxFps,
    maxParticles,
    pauseWhenHidden: true
  });

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) return;
    const waiters = hiddenWaiters;
    hiddenWaiters = [];
    waiters.forEach((callback) => window.requestAnimationFrame(callback));
  }, { passive: true });

  window.requestAnimationFrame = (callback) => {
    if (document.hidden) {
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
