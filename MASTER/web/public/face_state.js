// MASTER face state bridge: one semantic state for CLI, web HUD, 3D geometry and voice.
// The browser is a projection of the same state vocabulary the terminal reports.
// No renderer owns truth; this store owns the compact state vector and reflects it outward.
(() => {
  "use strict";

  const MODE_BUSY = /thinking|speaking|listening|scanning|routing|submit|anticipate|stream|stage|tool|working/i;
  const MODE_FAIL = /fail|error|blocked|unsafe|abort|crit|phantom|disconnected|veto/i;
  const MODE_WARN = /warn|risk|careful|retry|fallback/i;

  const FALLBACK_MODES = [
    "idle", "listening", "thinking", "working", "speaking",
    "warning", "error", "sleeping", "ready"
  ];

  const CONTRACT = window.MASTER_FACE_CONTRACT || {};
  const CONTRACT_STATE = CONTRACT.state || {};
  const CONTRACT_SPATIAL = CONTRACT.spatial || {};
  const CONTRACT_BUDGET = CONTRACT_SPATIAL.budget || {};
  const MODES = Object.freeze(Array.from(new Set(
    (Array.isArray(CONTRACT_STATE.modes) ? CONTRACT_STATE.modes : FALLBACK_MODES)
      .map((mode) => String(mode).toLowerCase())
      .filter(Boolean)
  )));
  const MODE_ALIASES = Object.freeze(Object.fromEntries(
    Object.entries(CONTRACT.mode_aliases || CONTRACT_STATE.mode_aliases || {})
      .map(([key, value]) => [String(key).toLowerCase(), String(value).toLowerCase()])
  ));
  const DEFAULTS = Object.freeze({
    mode: CONTRACT_STATE.default_mode || "idle",
    topology: CONTRACT_STATE.default_topology || "papua-mask",
    entropy: Number(CONTRACT_STATE.entropy ?? 0.18),
    confidence: Number(CONTRACT_STATE.confidence ?? 0.86),
    attention: Number(CONTRACT_STATE.attention ?? 1),
    arousal: Number(CONTRACT_STATE.arousal ?? 0.22),
    valence: Number(CONTRACT_STATE.valence ?? 0.18),
    focus: Number(CONTRACT_STATE.focus ?? 0.86),
    activity: Number(CONTRACT_STATE.activity ?? 0.14),
    risk: Number(CONTRACT_STATE.risk ?? 0),
    phase: "idle",
    provider: "unknown"
  });

  const state = { ...DEFAULTS };
  let lastEventAt = 0;

  const clamp = (value, fallback = 0.0, min = 0.0, max = 1.0) => {
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(min, Math.min(max, number)) : fallback;
  };

  function registryResult(text, detail = {}) {
    const registry = window.MASTERTopology;
    if (!registry || typeof registry.classifyEvent !== "function") return {};
    const name = String(detail.name || detail.mode || text || "event");
    try { return registry.classifyEvent(name, detail) || {}; } catch (_) { return {}; }
  }

  function modeFor(detail = {}) {
    const registry = registryResult(detail.name || detail.mode || "", detail);
    const explicit = String(detail.mode || "").toLowerCase();
    if (MODES.includes(explicit)) return explicit;
    const mapped = String(registry.mode || "").toLowerCase();
    if (MODES.includes(mapped)) return mapped;
    return MODE_ALIASES[mapped] || null;
  }

  function syncRuntimeFace() {
    const runtime = window.MASTER_FACE?.State;
    if (!runtime) return;

    runtime.mode = state.mode;
    runtime.entropy = state.entropy;
    runtime.confidence = state.confidence;
    runtime.attention = state.attention;
    runtime.arousal = state.arousal;
    runtime.valence = state.valence;
    runtime.focus = state.focus;
    runtime.activity = state.activity;
    runtime.risk = state.risk;
    runtime.phase = state.phase;
  }

  function reflect(detail = {}) {
    const root = document.documentElement;
    const body = document.body;
    if (!root || !body) return;

    root.dataset.masterMode = state.mode;
    root.dataset.masterTopology = state.topology;
    root.dataset.masterPhase = state.phase;
    root.dataset.masterRisk = state.risk.toFixed(2);
    root.dataset.masterConfidence = state.confidence.toFixed(2);
    root.style.setProperty("--master-entropy", state.entropy.toFixed(3));
    root.style.setProperty("--master-confidence", state.confidence.toFixed(3));
    root.style.setProperty("--master-attention", state.attention.toFixed(3));
    root.style.setProperty("--master-arousal", state.arousal.toFixed(3));
    root.style.setProperty("--master-valence", state.valence.toFixed(3));

    body.dataset.masterState = state.mode;
    body.dataset.visualRuntime = "face";
    body.dataset.mode = state.mode;

    const status = detail.status || state.phase;
    const element = document.getElementById("ui-status") || document.getElementById("zsh-status");
    if (element && status && detail.reflectStatus === true) element.textContent = String(status);
  }

  function apply(detail = {}) {
    const payload = detail && typeof detail === "object" ? detail : {};
    const text = String(payload.message || payload.text || payload.name || payload.mode || "");
    const registry = registryResult(text, payload);
    const explicitMode = modeFor(payload);

    state.mode = explicitMode || state.mode;
    state.topology = String(payload.canonical_topology || payload.topology || registry.topology || state.topology);
    state.entropy = clamp(payload.entropy ?? registry.entropy, state.entropy);
    state.confidence = clamp(payload.confidence ?? registry.confidence, state.confidence);
    state.attention = clamp(payload.attention, state.attention);
    state.arousal = clamp(payload.arousal ?? registry.arousal, state.arousal);
    state.valence = clamp(payload.valence, state.valence, -1, 1);
    state.focus = clamp(payload.focus ?? registry.focus, state.focus);
    state.activity = clamp(
      payload.activity,
      Math.min(1, 0.14 + state.entropy * 0.5 + (1 - state.confidence) * 0.35)
    );
    state.risk = clamp(payload.risk, Math.max(0, state.entropy * 0.8 + (1 - state.confidence) * 0.2));
    state.phase = String(payload.phase || payload.stage || payload.mode || state.mode || "idle");
    state.provider = String(payload.provider || state.provider || "unknown");
    lastEventAt = performance.now();

    syncRuntimeFace();
    reflect(payload);
    return snapshot();
  }

  function setMode(mode, detail = {}) {
    return apply({ ...detail, mode });
  }

  function setAttention(value) {
    state.attention = clamp(value, state.attention);
    document.documentElement.dataset.attention = state.attention.toFixed(2);
    syncRuntimeFace();
    reflect();
    return snapshot();
  }

  function snapshot() {
    return Object.freeze({
      ...state,
      age_ms: lastEventAt ? Math.max(0, performance.now() - lastEventAt) : 0
    });
  }

  // Geometry parameters are deliberately semantic rather than renderer-specific.
  // Any future WebGPU, SDF, splat or mesh projection gets the same numbers.
  function geometryProfile(snapshotValue = snapshot()) {
    const s = snapshotValue;
    const failure = Math.max(0, 1 - s.confidence);
    const busy = Math.max(s.activity, s.arousal);
    const risk = Math.min(1, Math.max(0, s.risk));
    return Object.freeze({
      shell_scale: 1 + (s.activity * 0.05) + failure * 0.08,
      shell_opacity: 0.10 + s.attention * 0.10 + s.confidence * 0.12,
      shell_tension: 0.18 + risk * 0.72,
      shell_pulse: 0.12 + busy * 0.48,
      shell_fracture: Math.max(0, risk - 0.30) * 1.65,
      eye_attention: 0.45 + s.attention * 0.55,
      eye_convergence: 0.12 + s.focus * 0.38,
      mouth_energy: 0.15 + s.arousal * 0.85,
      mouth_pressure: 0.08 + busy * 0.62,
      neural_density: 0.08 + s.activity * 0.92,
      node_energy: 0.14 + busy * 0.86,
      event_field: 0.10 + (s.entropy * 0.42) + (risk * 0.28),
      fracture: Math.max(0, risk - 0.35) * 1.54,
      camera_parallax: 0.015 + s.attention * 0.045,
      camera_distance: 5.20 - s.attention * 0.18 + risk * 0.12,
      depth: 0.60 + s.activity * 0.40
    });
  }

  function renderBudget() {
    const budget = CONTRACT_BUDGET;
    const mobile = matchMedia("(max-width: 767px)").matches || Number(navigator.hardwareConcurrency || 8) <= 4;
    const maxPoints = Number(budget[mobile ? "mobile_points" : "desktop_points"]) || (mobile ? 420 : 1200);
    const particles = Number(budget[mobile ? "mobile_particles" : "desktop_particles"]) || (mobile ? 120 : 200);
    const dpr = Math.min(Number(budget.max_device_pixel_ratio) || 2, Number(devicePixelRatio || 1));
    const reducedMotion = !!matchMedia("(prefers-reduced-motion: reduce)").matches;
    const reducedMotionParticles = Number(budget.reduced_motion_particles) || 64;
    const effectiveParticles = reducedMotion ? Math.min(particles, reducedMotionParticles) : particles;
    const profile = document.documentElement?.dataset?.runtimeProfile || "";
    const idle = state.mode === "idle" || state.mode === "sleeping";
    let fps = Number(idle ? budget.idle_fps : budget.active_fps) || (idle ? 12 : 24);
    if (reducedMotion) fps = Math.min(fps, Number(budget.reduced_motion_fps) || 8);
    if (profile === "battery") fps = Math.min(fps, Number(budget.battery_fps) || 12);
    return Object.freeze({
      points: maxPoints,
      particles: effectiveParticles,
      reduced_motion_particles: reducedMotionParticles,
      dpr,
      fps: document.hidden ? Number(budget.hidden_fps) || 0 : fps,
      pulse_limit: Number(budget.pulse_limit) || 24,
      hud_labels: Number(budget.hud_labels) || 5
    });
  }

  window.addEventListener("master:visual", (ev) => apply(ev.detail || {}), { passive: true });
  window.addEventListener("master:emotion", (ev) => apply(ev.detail || {}), { passive: true });

  window.addEventListener("tts:playback:start", () => setMode("speaking"));
  window.addEventListener("tts:playback:end", () => setMode("idle"));
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) return;
    apply({ mode: "idle", confidence: state.confidence, entropy: state.entropy });
  }, { passive: true });

  window.MASTER_FACE_STATE = Object.freeze({
    MODES,
    DEFAULTS,
    snapshot,
    apply,
    setMode,
    setAttention,
    geometryProfile,
    renderBudget
  });

  window.addEventListener("DOMContentLoaded", () => {
    apply({ mode: "idle", confidence: state.confidence, entropy: state.entropy });
  }, { once: true });
})();
