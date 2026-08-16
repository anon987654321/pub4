// Brutalist profile — raw monospace, step motion, exposed state strip (CLI + web parity).
(() => {
  "use strict";

  const PROFILES = window.MASTER_RUNTIME?.ui_philosophy?.profiles || [];
  const hasBrutalist = PROFILES.some((p) => (typeof p === "string" ? p : p.id) === "brutalist")
    || window.MASTER_RUNTIME?.enhancements?.includes?.("brutalist_profile");

  function applyWscons() {
    document.documentElement.dataset.runtimeProfile = "wscons";
    document.documentElement.style.setProperty("--transition-fast", "0ms");
    document.documentElement.style.setProperty("--transition-normal", "0ms");
    document.documentElement.style.setProperty("--ease-out", "steps(2,end)");
    document.documentElement.style.setProperty("--face-phosphor-decay", "0");
    document.documentElement.style.setProperty("--c-text", "#63c363");
    document.documentElement.style.setProperty("--x-text", "#63c363");
    document.body.classList.add("wscons-mode");
  }

  function applyBrutalist() {
    document.documentElement.dataset.runtimeProfile = "brutalist";
    document.documentElement.style.setProperty("--transition-fast", "0ms");
    document.documentElement.style.setProperty("--transition-normal", "0ms");
    document.documentElement.style.setProperty("--ease-out", "steps(2,end)");
    // Flat: no phosphor afterimage trail, no glow-halo expansion.
    document.documentElement.style.setProperty("--face-phosphor-decay", "0");
    document.documentElement.style.setProperty("--face-glow-scale", "1.0");
    document.body.classList.add("brutalist-mode");
  }

  const aesthetic = window.MASTER_RUNTIME?.aesthetic || document.documentElement.dataset.aesthetic || "brutalist";
  if (aesthetic === "wscons") applyWscons();
  else if (aesthetic !== "phosphor") applyBrutalist(); // brutalist (flat) default; phosphor keeps its glow CSS

  const primer = document.getElementById("primer");
  if (primer) {
    primer.addEventListener("pointerdown", () => {
      document.body.dataset.primerFlash = "1";
      setTimeout(() => delete document.body.dataset.primerFlash, 180);
    }, { passive: true });
  }

  const cursor = document.querySelector("#zin, #input");
  if (cursor) {
    let primerPulse = 0;
    setInterval(() => {
      primerPulse = (primerPulse + 1) % 2;
      const blink = document.querySelector(".cursor");
      if (!blink) return;
      const primerLive = document.getElementById("primer")?.classList.contains("gone");
      if (primerLive) blink.style.animationDuration = primerPulse ? "600ms" : "900ms";
    }, 450);
  }

  let idleSince = performance.now();
  const zin = document.getElementById("zin");
  setInterval(() => {
    if (!zin || document.activeElement === zin || zin.value) { idleSince = performance.now(); return; }
    if (performance.now() - idleSince < 18000) return;
    const hint = document.getElementById("idle-help-trail");
    if (!hint) {
      const el = document.createElement("div");
      el.id = "idle-help-trail";
      el.className = "idle-help-trail";
      el.textContent = "↓ ask";
      document.body.appendChild(el);
    }
    document.body.dataset.longSilence = "1";
  }, 2000);

  window.MASTER_BRUTALIST = Object.freeze({ apply: applyBrutalist });
})();
