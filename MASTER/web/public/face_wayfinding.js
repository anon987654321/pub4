"use strict";

(function () {
  const STEPS = ["audio", "face", "agent"];

  function tierFromMeta() {
    return document.querySelector('meta[name="master-tier"]')?.content || "visitor";
  }

  function strip() {
    return document.getElementById("boot-wayfinding");
  }

  function civic() {
    return document.getElementById("civic-status");
  }

  function stepEl(name) {
    return strip()?.querySelector(`[data-step="${name}"]`);
  }

  function setStep(name, state) {
    const el = stepEl(name);
    if (!el) return;
    el.dataset.state = state;
    const mark = el.querySelector(".boot-step-mark");
    if (mark) mark.textContent = state === "done" ? "✓" : "";
  }

  function setActive(name) {
    STEPS.forEach((step) => {
      const el = stepEl(step);
      if (!el || el.dataset.state === "done") return;
      el.dataset.state = step === name ? "active" : "pending";
    });
  }

  function showStrip() {
    const el = strip();
    if (!el || el.hidden === false) return;
    el.hidden = false;
    document.body.dataset.bootWayfinding = "1";
  }

  function hideStrip() {
    const el = strip();
    if (!el || el.hidden) return;
    el.dataset.fading = "1";
    window.setTimeout(() => {
      el.hidden = true;
      delete document.body.dataset.bootWayfinding;
      delete el.dataset.fading;
    }, 420);
  }

  function modelLabel() {
    return document.documentElement.dataset.modelProvider
      || document.querySelector('meta[name="master-model"]')?.content
      || "";
  }

  function updateCivic() {
    const el = civic();
    if (!el) return;
    const tier = tierFromMeta() === "authenticated" ? "full access" : "visitor";
    const ready = window.MASTER_CONTAINER_READY !== false;
    const model = modelLabel();
    el.textContent = ready && model ? `${tier} · ${model}` : `${tier} · warming`;
    el.hidden = false;
  }

  function onAudio() {
    setStep("audio", "done");
    setActive("face");
    showStrip();
    updateCivic();
  }

  function onFace() {
    setStep("face", "done");
    setActive("agent");
    updateCivic();
  }

  function onAgent(detail) {
    if (detail?.model) {
      document.documentElement.dataset.modelProvider = String(detail.model).slice(0, 24);
    }
    setStep("agent", "done");
    updateCivic();
  }

  function onSession() {
    hideStrip();
  }

  function syncFromState() {
    if (window._primerFired || window.MASTER_FACE?.primerFired) {
      setStep("audio", "done");
      showStrip();
      setActive("face");
    }
    if (document.body.classList.contains("face-ready") || window.FACE3D_ACTIVE) {
      setStep("face", "done");
      setActive("agent");
    }
    if (window.MASTER_CONTAINER_READY) {
      onAgent({ model: modelLabel() });
    }
    if (window.MASTER_FACE?.primerFired && document.body.classList.contains("face-session")) {
      updateCivic();
    }
  }

  window.addEventListener("primer:ready", onAudio);
  window.addEventListener("master:face-ready", onFace, { once: true });
  window.addEventListener("master:container-ready", (ev) => onAgent(ev.detail || {}), { once: true });
  window.addEventListener("master:session-ready", onSession, { once: true });

  syncFromState();
})();