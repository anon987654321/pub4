// MASTER visual governor: cap animation pressure before mask.js loads.
(() => {
  const maxFps = 24;
  const minFrameMs = 1000 / maxFps;
  const nativeRaf = window.requestAnimationFrame.bind(window);
  let last = 0;

  window.MASTER_VISUAL_LIMITS = Object.freeze({
    maxFps,
    maxParticles: 200,
    pauseWhenHidden: true
  });

  window.requestAnimationFrame = (callback) => nativeRaf((now) => {
    if (document.hidden) {
      last = now;
      return nativeRaf(() => callback(now));
    }
    if (now - last < minFrameMs) {
      return nativeRaf(() => window.requestAnimationFrame(callback));
    }
    last = now;
    callback(now);
  });
})();
