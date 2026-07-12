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
    document.documentElement.style.setProperty("--face-phosphor-decay", "0.55");
    document.body.classList.add("brutalist-mode");
  }

  const aesthetic = window.MASTER_RUNTIME?.aesthetic || document.documentElement.dataset.aesthetic;
  if (aesthetic === "wscons") applyWscons();
  else if (hasBrutalist || new URLSearchParams(location.search).get("brutalist") === "1") applyBrutalist();

  let strip = document.getElementById("brutalist-strip");
  if (!strip) {
    strip = document.createElement("pre");
    strip.id = "brutalist-strip";
    strip.className = "brutalist-strip";
    strip.setAttribute("aria-hidden", "true");
    document.body.appendChild(strip);
  }

  const ring = [];
  function pushLine(tag, val) {
    ring.push(`${tag}=${val}`);
    while (ring.length > 6) ring.shift();
    strip.textContent = ring.join(" ");
  }

  window.addEventListener("master:visual", (ev) => {
    const d = ev.detail || {};
    pushLine("mode", (d.mode || "idle").toString().slice(0, 12));
    if (d.entropy != null) pushLine("H", Number(d.entropy).toFixed(2));
    if (d.confidence != null) pushLine("C", Number(d.confidence).toFixed(2));
  });

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

  window.MASTER_BRUTALIST = Object.freeze({ apply: applyBrutalist, pushLine });
})();