// Micro-interaction bridge — ecology orbit, crown spawns, streaming nudges (web_011–web_025).
(() => {
  "use strict";

  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const cv = document.getElementById("face");
  const K = () => window.ParticleKernel;
  const face = () => window.MASTER_FACE;
  const st = () => face()?.State;
  const eyePool = () => face()?.eyePool || window.eyePool;
  const mouthPool = () => face()?.mouthPool || window.mouthPool;

  function boostEye(delta = 0.12) {
    const pool = eyePool();
    const kernel = K();
    if (!pool || !kernel) return;
    for (let i = 0; i < pool.count; i++) if (pool.alive[i]) {
      const b = i * kernel.FIELDS_PER_CELL;
      pool.cells[b + kernel.FIELD.attention] = Math.min(1, (pool.cells[b + kernel.FIELD.attention] || 0.5) + delta);
    }
  }

  function spawnCrown(n = 2, opts = {}) {
    const pool = eyePool();
    const kernel = K();
    if (!pool || !kernel) return;
    for (let i = 0; i < n; i++) {
      kernel.spawn(pool, (Math.random() - 0.5) * 0.35, -0.55 + Math.random() * 0.12, {
        kind: 3,
        zone: 13,
        valence: opts.valence ?? 0.35,
        confidence: opts.confidence ?? 0.82,
        attention: opts.attention ?? 0.7,
        decay: opts.decay ?? 0.007
      });
    }
  }

  function mouthPressure(delta = 0.18) {
    const pool = mouthPool();
    const kernel = K();
    if (!pool || !kernel) return;
    for (let i = 0; i < pool.count; i++) if (pool.alive[i]) {
      const b = i * kernel.FIELDS_PER_CELL;
      pool.cells[b + kernel.FIELD.pressure] = Math.min(1, (pool.cells[b + kernel.FIELD.pressure] || 0) + delta);
    }
  }

  // web_011 — ecology orbit tightens with kernel attention
  setInterval(() => {
    const ecology = window.MASTEREcology;
    if (!ecology?.agents) return;
    const pool = eyePool();
    const kernel = K();
    if (!pool || !kernel) return;
    let attn = 0, n = 0;
    for (let i = 0; i < pool.count; i++) if (pool.alive[i]) {
      const b = i * kernel.FIELDS_PER_CELL;
      attn += pool.cells[b + kernel.FIELD.attention] || 0;
      n++;
    }
    if (!n) return;
    const focus = attn / n;
    const tighten = 0.88 + focus * 0.12;
    ecology.agents.forEach((agent) => {
      const base = agent._radiusBase ?? agent.radius;
      agent._radiusBase = base;
      agent.radius = base * tighten;
    });
  }, 520);

  // web_012 / web_025 — memory + photo-ready crown cells
  window.addEventListener("master:visual", (ev) => {
    const name = String(ev.detail?.name || ev.detail?.mode || "");
    if (/memory|retriev|context|compact/.test(name)) spawnCrown(2, { valence: 0.42 });
    if (/photo:ready|input:photo/.test(name)) spawnCrown(3, { valence: 0.55, confidence: 0.9 });
  });

  // web_013 — reduced-motion low-amplitude breaths
  const breathScale = reducedMotion ? 0.42 : 1;
  setInterval(() => {
    const state = st();
    if (!state) return;
    if (state._breathScale == null) state._breathScale = breathScale;
    state.breath = Math.min(1.4, (state.breath || 1) * state._breathScale + (1 - state._breathScale) * 0.08);
  }, 900);

  // web_014 — mouse tilt biases eye mask position
  if (cv) {
    cv.addEventListener("pointermove", (e) => {
      const state = st();
      if (!state) return;
      const nx = (e.clientX / innerWidth - 0.5) * 2;
      const ny = (e.clientY / innerHeight - 0.5) * 2;
      state.eyeMaskBiasX = (state.eyeMaskBiasX || 0) * 0.82 + nx * 0.06;
      state.eyeMaskBiasY = (state.eyeMaskBiasY || 0) * 0.82 + ny * 0.04;
      if (face()?.faceMat?.uniforms?.uMouse) {
        face().faceMat.uniforms.uMouse.value.x = nx;
        face().faceMat.uniforms.uMouse.value.y = ny;
      }
    }, { passive: true });
  }

  // web_015 — face edge hover peripheral arousal
  if (cv) {
    cv.addEventListener("pointermove", (e) => {
      const edge = Math.min(e.clientX, innerWidth - e.clientX, e.clientY, innerHeight - e.clientY);
      if (edge > 72) return;
      const state = st();
      if (!state) return;
      state.pulse = Math.max(state.pulse || 0, 0.08 + (1 - edge / 72) * 0.22);
    }, { passive: true });
  }

  // web_018 — reduced-motion sinusoidal eye scan
  if (reducedMotion) {
    let phase = 0;
    setInterval(() => {
      phase += 0.08;
      const state = st();
      if (!state) return;
      state.mouseX = Math.sin(phase) * 0.35;
      state.mouseY = Math.cos(phase * 0.7) * 0.18;
      boostEye(0.03);
    }, 120);
  }

  // web_020 — streaming nudges eye attention
  window.addEventListener("chat:chunk", () => boostEye(0.05));
  const origChunk = window._chatOnChunk;
  if (typeof origChunk === "function") {
    window._chatOnChunk = (raw) => {
      window.dispatchEvent(new CustomEvent("chat:chunk", { detail: { raw } }));
      if (/[.!?]\s*$/.test(String(raw || ""))) mouthPressure(0.14);
      return origChunk(raw);
    };
  }

  // web_021 — sentence-end mouthPool pressure handled in chunk wrapper above

  // web_022 — veto/pass ecology calm burst
  window.addEventListener("chat:dmesg", (ev) => {
    const line = String(ev.detail?.line || "");
    if (!/veto|pass/i.test(line)) return;
    window.MASTEREcology?.burst?.(5, /pass/i.test(line) ? 0.18 : 0.32);
    if (/pass/i.test(line)) boostEye(0.08);
    else mouthPressure(-0.12);
  });

  // web_023 — STT start eye attention boost (augments face.part5)
  window.addEventListener("master:visual", (ev) => {
    if (/stt:start|listening/.test(String(ev.detail?.name || ev.detail?.mode || ""))) boostEye(0.18);
  });

  // web_024 / f3d_006 — mouthDrive via blendshape bridge (replaces direct mouth mutation)
  setInterval(() => {
    const state = st();
    if (!state) return;
    const drive = Math.min(1, (state.mouthDrive || 0) + (state.visemeAmp || 0) * 0.35);
    window.MASTER_FACE_BLEND?.applyMouthDrive?.(drive, state.visemeAmp || 0);
    const mat = face()?.faceMat;
    if (mat?.uniforms?.uJaw) mat.uniforms.uJaw.value = Math.max(mat.uniforms.uJaw.value, drive * 0.42);
  }, 48);

  // mi_073 — dynamic canvas aria-label from state
  setInterval(() => {
    if (!cv) return;
    const state = st();
    const mode = state?.mode || document.documentElement.dataset.masterMode || "idle";
    const conf = Number(document.documentElement.style.getPropertyValue("--master-confidence") || 0.86);
    cv.setAttribute("aria-label", `MASTER face — ${mode}, confidence ${Math.round(conf * 100)}%`);
  }, 2000);

  window.MASTER_FACE_MICRO = Object.freeze({ boostEye, spawnCrown, mouthPressure });
})();
