(() => {
  "use strict";

// The decorative layers are gone.
//
// drawSemanticTerrain drew thirteen rows of stroked contour, drawAgentSpirits
// outlined each agent with strokeRect, drawTrails and drawWeather added more
// strokes on top. All of it was line work in the background of a face that is
// deliberately nothing but points — "lines outside in the background, that's
// not brutalist at all" (operator, 2026-08-27).
//
// The state they drew from still lives in cognition_ecology.js and is still
// updated; only the drawing is deleted. Nothing read these functions but the
// frame loop, and the frame loop no longer calls them.
  function eco() {
    return window.MASTEREcology;
  }





  function drawMemories(dt, E) {
    const { memories, ctx, internalW, internalH } = E;
    for (let i = memories.length - 1; i >= 0; i--) {
      const memory = memories[i];
      memory.life -= dt * 0.00018;
      memory.pulse += dt * 0.002;
      if (memory.life <= 0) {
        memories.splice(i, 1);
        continue;
      }
      const alpha = memory.life * (0.16 + Math.sin(memory.pulse) * 0.05);
      const sz = (2 + memory.z * 3) | 0;
      ctx.fillStyle = `rgba(220,205,175,${alpha})`;
      ctx.fillRect((memory.x - sz * 0.5) | 0, (memory.y - sz * 0.5) | 0, sz, sz);

// No constellation. This drew a stroke between every pair of memories inside
// a radius — the particle-network effect — which is "lines in between the
// particle dots" (operator, 2026-08-27) on a surface whose whole idea is
// that it is points and nothing else. The memories still exist and still
// draw; what is gone is the pretence that they are connected.
    }
  }


  let previous = performance.now();
  let ecologyFrameActive = false;
  function ensureEcologyFrame() {
    if (ecologyFrameActive || document.hidden) return;
    ecologyFrameActive = true;
    requestAnimationFrame(frame);
  }

  function frame(now) {
    const E = eco();
    if (!E) {
      if (!document.hidden) requestAnimationFrame(frame);
      else ecologyFrameActive = false;
      return;
    }
    if (document.hidden) {
      previous = now;
      ecologyFrameActive = false;
      return;
    }
    const dt = Math.min(48, now - previous);
    previous = now;
    E.state.time = now;
    E.state.activity += (((now - E.state.lastEventAt) < 3200 ? 0.72 : 0.16) - E.state.activity) * 0.012;

    const focusMode = document.body?.dataset.focusMode === "1";
    const speaking = document.body?.dataset.mode === "speaking";
    let ecologyAlpha = focusMode ? 0.14 : (document.body?.dataset.longSilence === "1" ? 0.55 : 1.0);
    if (speaking) ecologyAlpha *= 0.32;
    E.canvas.style.opacity = String(ecologyAlpha);

    const { ctx, canvas } = E;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.globalCompositeOperation = "lighter";
    drawMemories(dt, E);

    if (!E.reducedMotion && !speaking && Math.random() < 0.025 + E.state.activity * 0.025) {
      E.spawnWeatherBurst(1, 0.25 + E.state.activity * 0.5);
    }
    if (!document.hidden) requestAnimationFrame(frame);
    else ecologyFrameActive = false;
  }

  ensureEcologyFrame();
  window.addEventListener("master:visual", () => ensureEcologyFrame(), { passive: true });
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) ensureEcologyFrame();
  }, { passive: true });
})();
