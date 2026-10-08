// Accessibility projection for the face.
// Core state stays in MasterInteraction; this module only exposes it semantically.
(() => {
  "use strict";

  function liveRegion(id, politeness = "polite") {
    let node = document.getElementById(id);
    if (node) return node;
    node = document.createElement("div");
    node.id = id;
    node.className = "sr-only";
    node.setAttribute("aria-live", politeness);
    node.setAttribute("aria-atomic", "true");
    document.body.appendChild(node);
    return node;
  }

  function reflectMic(state) {
    const node = document.getElementById("mic-dot");
    if (!node) return;
    const text = node.querySelector("[data-mic-state-text]");
    const label = "microphone " + String(state);
    node.dataset.captureState = state;
    node.setAttribute("aria-label", label);
    if (text) text.textContent = label;
  }

  function announce(text) {
    if (!text) return;
    liveRegion("master-state-live").textContent = String(text);
  }

  function install() {
    const root = document.documentElement;
    const reduced = matchMedia?.("(prefers-reduced-motion: reduce)");
    if (reduced) {
      root.dataset.reducedMotion = reduced.matches ? "1" : "0";
      reduced.addEventListener?.("change", (event) => { root.dataset.reducedMotion = event.matches ? "1" : "0"; });
    }
    if (matchMedia?.("(forced-colors: active)")?.matches) root.dataset.forcedColors = "1";
    if (matchMedia?.("(prefers-contrast: more)")?.matches) root.dataset.highContrast = "1";

    const input = document.getElementById("zin");
    if (input) {
      input.setAttribute("aria-describedby", "master-input-status");
      liveRegion("master-input-status");
      input.addEventListener("focus", () => {
        window.MasterInteraction?.setInteraction?.("idle", { source: "keyboard-focus" });
      });
    }
  }

  window.addEventListener("interaction:state", (event) => {
    const state = event.detail?.state;
    reflectMic(state === "listening" ? "listening" : state === "processing" ? "processing" : "closed");
    if (["waking", "listening", "processing", "speaking", "error"].includes(state)) announce(state);
  });
  window.addEventListener("performance:receipt", (event) => {
    if (event.detail?.kind === "first-response") announce("response started");
  });
  window.addEventListener("task:failed", () => announce("task failed; recovery is available"));
  window.addEventListener("task:complete", () => announce("task complete"));

  install();
  window.MASTER_ACCESSIBILITY = Object.freeze({ install, liveRegion, announce });
})();
