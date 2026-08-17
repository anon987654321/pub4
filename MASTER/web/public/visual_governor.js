// MASTER visual governor: state-aware animation pressure control before mask.js loads.
//
// These numbers are the source. The header used to say "Limits sourced from
// data/ops/visual.yml (SINGULARITY / ONE_SOURCE). Do not duplicate." and nothing
// here read that file: 930a35ca5, a revert to fix tap-to-start, removed the
// `window.MASTER_RUNTIME.visual_limits` read as collateral and the comment
// survived it. The file then drifted on all five values, including
// freeze_on_fail: true against the freezeOnFail: false below -- so honouring
// that comment would have restored the black deployed face it was fixed for.
// The file is deleted; this is the one place the limits live.
(() => {
  // Restored with the read, from the same revert. Every other visual module
  // checks this media query for itself, so the governor's cap is the floor
  // under all of them rather than the only guard.
  const reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches;
  // documentElement, not body: face_brutalist.js and face_vision_d.js both write
  // runtimeProfile there. The pre-revert version read body.dataset and so never
  // saw a profile at all.
  const profile = document.documentElement?.dataset?.runtimeProfile
    || document.querySelector('meta[name="master-visual-profile"]')?.content
    || "auto";

  let maxFps = 24;
  let maxParticles = 200;
  const reducedMotionParticles = 64;
  if (reducedMotion) maxFps = Math.min(maxFps, 8);
  else if (profile === "battery") maxFps = Math.min(maxFps, 12);
  if (reducedMotion) maxParticles = reducedMotionParticles;
  const minFrameMs = 1000 / maxFps;
  const nativeRaf = window.requestAnimationFrame.bind(window);
  const nativePush = Array.prototype.push;
  let last = 0;
  let hiddenWaiters = [];
  // Every caller shares one native frame, and a passing frame releases all of
  // them together. Gating each callback against a shared `last` instead lets
  // whichever loop registers first reset the clock every frame, so every other
  // loop reads now-last === 0 forever and never gets a single frame -- the face
  // renders and the ecology canvas beside it sits frozen.
  let pending = new Map();
  let nextId = 1;
  let nativeHandle = 0;

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
    waiters.forEach(({ id, callback }) => pending.set(id, callback));
    pump();
  }, { passive: true });

  function runFrame(now) {
    nativeHandle = 0;
    if (now - last < minFrameMs) { pump(); return; }
    last = now;
    const batch = pending;
    pending = new Map();
    batch.forEach((callback) => {
      // One throwing callback must not swallow the rest of the frame; rethrow
      // async so the browser still reports it as an uncaught error.
      try { callback(now); } catch (err) { setTimeout(() => { throw err; }); }
    });
  }

  function pump() {
    if (nativeHandle || pending.size === 0) return;
    nativeHandle = nativeRaf(runFrame);
  }

  window.requestAnimationFrame = (callback) => {
    const id = nextId;
    nextId += 1;
    if (document.hidden || frozen()) {
      hiddenWaiters.push({ id, callback });
      return id;
    }
    pending.set(id, callback);
    pump();
    return id;
  };

  // The ids above are ours, so cancellation has to be ours too: handing back a
  // native handle that a re-queue had already replaced made cancel a silent
  // no-op.
  window.cancelAnimationFrame = (id) => {
    pending.delete(id);
    hiddenWaiters = hiddenWaiters.filter((waiter) => waiter.id !== id);
  };
})();
