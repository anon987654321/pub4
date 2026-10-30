// MASTER visual governor: one frame check for the canonical face budget.
// FaceState owns semantic state and resolves device, motion and runtime limits;
// this module applies that policy to the shared requestAnimationFrame clock.
(() => {
  "use strict";

  const CONTRACT = window.MASTER_FACE_CONTRACT || {};
  const BUDGET = CONTRACT.spatial?.budget || {};
  const reducedMotionQuery = window.matchMedia?.("(prefers-reduced-motion: reduce)");
  const nativeRaf = window.requestAnimationFrame.bind(window);
  let last = 0;
  let hiddenWaiters = [];
  // Every caller shares one native frame, and a passing frame releases all of
  // them together. Gating each callback against a shared clock keeps concurrent
  // render loops in step instead of starving whichever loop registers second.
  let pending = new Map();
  let nextId = 1;
  let nativeHandle = 0;
  let limits = Object.freeze({
    maxFps: Number(BUDGET.active_fps) || 24,
    maxParticles: Number(BUDGET.desktop_particles) || 200,
    reducedMotionParticles: Number(BUDGET.reduced_motion_particles) || 64,
    constrainedDevice: false,
    reducedMotion: false,
    pauseWhenHidden: true,
    freezeOnFail: false
  });

  function frozen() {
    // A backend fail (TTS/replicate/health) must not black out the face.
    return document.body?.dataset.visualRuntime === "frozen";
  }

  function resolveLimits() {
    const faceState = window.MASTER_FACE_STATE;
    const snapshot = faceState?.snapshot?.() || {};
    const canonicalBudget = faceState?.renderBudget?.() || {};
    const reducedMotion = typeof faceState?.reducedMotion === "function"
      ? faceState.reducedMotion(snapshot)
      : Boolean(snapshot.reducedMotion)
        || document.documentElement?.dataset?.reducedMotion === "1"
        || Boolean(reducedMotionQuery?.matches);
    const mobile = canonicalBudget.constrained_device !== undefined
      ? Boolean(canonicalBudget.constrained_device)
      : Boolean(window.matchMedia?.("(pointer: coarse)")?.matches)
        || Boolean(window.matchMedia?.("(max-width: 767px)")?.matches)
        || Number(globalThis.navigator?.hardwareConcurrency || 8) <= 4;
    const profile = document.documentElement?.dataset?.runtimeProfile
      || document.querySelector('meta[name="master-visual-profile"]')?.content
      || "auto";
    const idle = ["idle", "sleeping", "ready"].includes(String(snapshot.mode || document.body?.dataset?.mode || "").toLowerCase());
    const activeFps = Number(BUDGET.active_fps) || 24;
    const idleFps = Number(BUDGET.idle_fps) || 12;
    const reducedMotionFps = Number(BUDGET.reduced_motion_fps) || 8;
    const batteryFps = Number(BUDGET.battery_fps) || 12;
    let maxFps = Number(canonicalBudget.fps) || (idle ? idleFps : activeFps);
    let maxParticles = Number(canonicalBudget.particles)
      || Number(BUDGET[mobile ? "mobile_particles" : "desktop_particles"])
      || (mobile ? 120 : 200);
    const reducedMotionParticles = Number(BUDGET.reduced_motion_particles) || 64;

    if (reducedMotion) {
      maxFps = Math.min(maxFps, reducedMotionFps);
      maxParticles = Math.min(maxParticles, reducedMotionParticles);
    } else if (profile === "battery") {
      maxFps = Math.min(maxFps, batteryFps);
    }

    limits = Object.freeze({
      maxFps,
      maxParticles,
      reducedMotionParticles,
      constrainedDevice: mobile,
      reducedMotion,
      pauseWhenHidden: true,
      freezeOnFail: false
    });
    window.MASTER_VISUAL_LIMITS = limits;
    return limits;
  }

  function publishLimits() {
    return resolveLimits();
  }

  publishLimits();

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) return;
    const waiters = hiddenWaiters;
    hiddenWaiters = [];
    waiters.forEach(({ id, callback }) => pending.set(id, callback));
    pump();
  }, { passive: true });

  function runFrame(now) {
    nativeHandle = 0;
    const current = resolveLimits();
    const minFrameMs = 1000 / Math.max(1, current.maxFps);
    if (now - last < minFrameMs) { pump(); return; }
    last = now;
    const batch = pending;
    pending = new Map();
    batch.forEach((callback) => {
      // One throwing callback must not swallow the rest of the frame.
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

  // The ids above are ours, so cancellation has to be ours too.
  window.cancelAnimationFrame = (id) => {
    pending.delete(id);
    hiddenWaiters = hiddenWaiters.filter((waiter) => waiter.id !== id);
  };

  // Re-evaluate immediately when a semantic state or accessibility preference
  // changes; runFrame also refreshes before applying the next frame ceiling.
  window.addEventListener("master:visual", publishLimits, { passive: true });
  window.addEventListener("master:emotion", publishLimits, { passive: true });
  window.addEventListener("master:face-state", publishLimits, { passive: true });
  reducedMotionQuery?.addEventListener?.("change", publishLimits);
  document.addEventListener("visibilitychange", publishLimits, { passive: true });

  window.MASTER_VISUAL_LIMITS = limits;
})();
