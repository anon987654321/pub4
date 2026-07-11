"use strict";

// LAUI engagement rail — ar5iv:2405.13050 (thought/action/speech lanes)
// + GenAI UI survey ar5iv:2410.22370 (prompt vs input modalities).
(() => {
  const LANES = ["thought", "action", "speech"];
  const MODE_LABELS = {
    idle: "idle",
    attending: "listen",
    thinking: "think",
    tool: "act",
    speaking: "speak",
    complete: "done",
    error: "error",
    phantom: "uncertain",
    council: "council",
    palette: "palette"
  };

  let root = document.getElementById("agent-hud");
  if (!root) {
    root = document.createElement("aside");
    root.id = "agent-hud";
    root.className = "agent-hud";
    root.setAttribute("aria-label", "Agent engagement");
    root.innerHTML =
      '<div class="agent-hud-engagement" data-agent-hud="engagement" aria-live="polite"></div>' +
      '<div class="agent-hud-lanes" data-agent-hud="lanes" aria-hidden="true">' +
      LANES.map((lane) => `<span class="agent-lane" data-lane="${lane}">${lane}</span>`).join("") +
      "</div>" +
      '<div class="agent-hud-modalities" data-agent-hud="modalities" aria-hidden="true"></div>' +
      '<p class="agent-hud-hint" data-agent-hud="hint"></p>';
    document.body.appendChild(root);
  }

  const engagementEl = root.querySelector('[data-agent-hud="engagement"]');
  const lanesEl = root.querySelector('[data-agent-hud="lanes"]');
  const modalitiesEl = root.querySelector('[data-agent-hud="modalities"]');
  const hintEl = root.querySelector('[data-agent-hud="hint"]');

  const state = {
    mode: "idle",
    lanes: { thought: 0, action: 0, speech: 0 },
    modalities: new Set(["prompt"]),
    hint: "",
    toolCount: 0
  };

  function laneForEvent(name = "", detail = {}) {
    const text = `${name} ${JSON.stringify(detail)}`.toLowerCase();
    if (/tts:|speak|playback/.test(text)) return "speech";
    if (/tool|scan|sweep|pipeline:stage|agent:|route:|infer:/.test(text)) return "action";
    if (/thought|council|phantom|reason/.test(text)) return "thought";
    if (/stream|chunk|response|done|complete/.test(text)) return "speech";
    return null;
  }

  function pulseLane(lane) {
    if (!lane || !lanesEl) return;
    state.lanes[lane] = Math.min(1, (state.lanes[lane] || 0) + 0.35);
    const el = lanesEl.querySelector(`[data-lane="${lane}"]`);
    if (el) {
      el.dataset.active = "1";
      setTimeout(() => delete el.dataset.active, 420);
    }
  }

  function decayLanes() {
    LANES.forEach((lane) => {
      state.lanes[lane] = Math.max(0, (state.lanes[lane] || 0) - 0.04);
      const el = lanesEl?.querySelector(`[data-lane="${lane}"]`);
      if (el) el.style.opacity = String(0.25 + state.lanes[lane] * 0.75);
    });
  }

  function setMode(mode) {
    state.mode = mode || "idle";
    const label = MODE_LABELS[state.mode] || state.mode;
    if (engagementEl) engagementEl.textContent = label;
    document.documentElement.dataset.agentEngagement = state.mode;
    root.dataset.mode = state.mode;
  }

  function renderModalities() {
    if (!modalitiesEl) return;
    modalitiesEl.innerHTML = "";
    state.modalities.forEach((mod) => {
      const chip = document.createElement("span");
      chip.className = "agent-modality";
      chip.dataset.modality = mod;
      chip.textContent = mod;
      modalitiesEl.appendChild(chip);
    });
  }

  function addModality(mod) {
    if (!mod) return;
    state.modalities.add(mod);
    renderModalities();
  }

  function removeModality(mod) {
    if (!mod || mod === "prompt") return;
    state.modalities.delete(mod);
    renderModalities();
  }

  function applyResearch(runtime) {
    const research = runtime?.face_research;
    if (!research) return;
    const hints = Array.isArray(research.proactive_hints) ? research.proactive_hints : [];
    if (!hints.length) return;
    state.hint = hints[Math.floor(Math.random() * hints.length)];
    if (hintEl) hintEl.textContent = state.hint;
    window.MASTER_FACE_RESEARCH = research;
  }

  function placeholdersFromResearch(runtime) {
    const mods = runtime?.face_research?.modalities;
    if (!Array.isArray(mods) || !mods.length) return null;
    return mods.map((m) => m.placeholder).filter(Boolean);
  }

  window.addEventListener("master:runtime-config", (ev) => {
    applyResearch(ev.detail || window.MASTER_RUNTIME);
    const ph = placeholdersFromResearch(ev.detail || window.MASTER_RUNTIME);
    if (ph?.length) window.MASTER_AGENT_PLACEHOLDERS = ph;
  });

  if (window.MASTER_RUNTIME?.face_research) applyResearch(window.MASTER_RUNTIME);

  window.addEventListener("master:visual", (ev) => {
    const detail = ev.detail || {};
    const mode = detail.mode || detail.name || "event";
    setMode(mode);
    const lane = laneForEvent(detail.name || "", detail);
    if (lane) pulseLane(lane);
    if (/tool|scan|sweep/.test(`${detail.name} ${detail.mode}`)) {
      state.toolCount += 1;
      addModality("tool");
    }
    if (/complete|done|idle/.test(mode)) {
      state.toolCount = 0;
      removeModality("tool");
    }
  });

  document.addEventListener("chat:dmesg", (ev) => {
    const line = String(ev.detail?.line || "");
    const lane = laneForEvent(line, {});
    if (lane) pulseLane(lane);
  });

  const photoBtn = document.getElementById("photo-button");
  if (photoBtn) {
    photoBtn.addEventListener("click", () => addModality("photo"), { passive: true });
    new MutationObserver(() => {
      const st = photoBtn.dataset.state;
      if (st === "ready" || st === "raw") addModality("photo");
      else if (!st) removeModality("photo");
    }).observe(photoBtn, { attributes: true, attributeFilter: ["data-state"] });
  }

  const micBtn = document.querySelector('[data-act="mic"]');
  if (micBtn) {
    micBtn.addEventListener("click", () => {
      if (micBtn.classList.contains("active")) addModality("voice");
      else removeModality("voice");
    });
  }

  const input = document.getElementById("zin");
  if (input) {
    input.addEventListener("focus", () => addModality("prompt"), { passive: true });
    input.addEventListener("input", () => {
      if (/```|function |class |def |import /.test(input.value)) addModality("code");
      else removeModality("code");
    }, { passive: true });
  }

  setInterval(decayLanes, 120);
  setMode("idle");
  renderModalities();

  window.MASTERAgentHud = {
    setMode,
    pulseLane,
    placeholdersFromResearch,
    state: () => ({ ...state, modalities: [...state.modalities] })
  };
})();