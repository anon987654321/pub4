// MASTER visual governor: cap animation pressure before mask.js loads.
(() => {
  const maxFps = 24;
  const minFrameMs = 1000 / maxFps;
  const nativeRaf = window.requestAnimationFrame.bind(window);
  let last = 0;
  let hiddenWaiters = [];

  window.MASTER_VISUAL_LIMITS = Object.freeze({
    maxFps,
    maxParticles: 200,
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
