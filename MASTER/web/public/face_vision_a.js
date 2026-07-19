// MASTER particle face 2026 — vision features 1–40 (semantic, TTS, fusion).
(() => {
  "use strict";

  const V = window.MASTER_FACE_VISION;
  if (!V) return;

  const STAGE_KINDS = {
    intake: 0, enhance: 1, infer: 2, route: 3, guard: 4, execute: 5,
    council: 6, lint: 7, prune: 8, memo: 9, render: 10,
  };

  const VISEME_CORNERS = { A: 0.42, E: 0.28, I: 0.55, O: 0.18, M: 0.08, U: 0.14, neutral: 0.12 };
  const STYLE_DECAY = { calm: 0.88, dramatic: 0.72, whisper: 0.94, energetic: 0.78, intimate: 0.91 };

  function blend() {
    return window.MASTER_FACE_BLEND;

  function providerAccent(provider) {
    const palette = window.MASTEREvents?.paletteForProvider?.(provider);
    return palette?.accent || "#f5f0e8";

  // 1–20 semantic
  V.register(1, "pipeline stage kinds", (ctx) => {
    const label = String(ctx.detail.stage || ctx.detail.mode || ctx.type || "idle").toLowerCase();
    const kind = STAGE_KINDS[label.split(/[:\s]/)[0]] ?? 0;
    ctx.st.pipelineStage = label;
    document.documentElement.dataset.pipelineStage = label.slice(0, 24);
    document.documentElement.dataset.pipelineKind = String(kind);
    V.spawn(2, { kind, zone: 2, confidence: 0.7, attention: 0.5, decay: 0.018 });,
  });

  V.register(2, "council burst", (ctx) => {
    const entropy = Number(ctx.detail.entropy ?? ctx.st.entropy ?? 0.35);
    ctx.st.pulse = Math.max(ctx.st.pulse || 0, 0.42 + entropy * 0.2);
    for (let n = 0; n < 3; n++) {
      V.spawn(3, { kind: 3, arousal: 0.55, valence: 0.1, pressure: entropy, vx: (n - 1) * 0.014, decay: 0.016 });,
    }
    document.documentElement.dataset.councilBurst = "1";
    window.setTimeout(() => { delete document.documentElement.dataset.councilBurst; }, 480);,
  });

  V.register(3, "pressure radial flow", (ctx) => {
    const pct = Number(ctx.detail.pct ?? ctx.detail.raw?.pct ?? ctx.st.pressureFields?.pct ?? 0);
    const radial = Math.min(1, pct / 100);
    ctx.st.pressureFields = { ...(ctx.st.pressureFields || {}), pct, radial };
    V.css("--master-pressure-radial", radial.toFixed(3));
    V.spawn(4, { kind: 4, pressure: radial, vy: -radial * 0.02, confidence: 0.6, decay: 0.02 });,
  });

  V.register(4, "valence zone tint", (ctx) => {
    const valence = Number(ctx.detail.valence ?? ctx.st.expressionCurrent?.valence ?? 0);
    const tint = valence >= 0 ? `rgba(180,220,160,${0.08 + valence * 0.12})` : `rgba(220,140,140,${0.08 + Math.abs(valence) * 0.12})`;
    V.css("--face-valence-tint", tint);
    document.documentElement.dataset.valenceSign = valence >= 0 ? "pos" : "neg";,
  });

  V.register(5, "confidence size", (ctx) => {
    const conf = Number(ctx.detail.confidence ?? ctx.st.confidence ?? 0.75);
    ctx.st.confidence = conf;
    const scale = 0.72 + conf * 0.42;
    V.css("--face-confidence-scale", scale.toFixed(3));
    document.documentElement.dataset.confidenceBand = conf > 0.85 ? "high" : conf < 0.35 ? "low" : "mid";,
  });

  V.register(6, "attention pull", (ctx) => {
    const attn = Number(ctx.detail.attention ?? 0.65);
    ctx.st.expressionTarget = { ...(ctx.st.expressionTarget || {}), attention: attn };
    V.spawn(2, { kind: 6, attention: attn, vx: -attn * 0.01, vy: attn * 0.006, confidence: 0.8, decay: 0.014 });
    document.documentElement.dataset.attentionPull = "1";,
  });

  V.register(7, "arousal repel", (ctx) => {
    const arousal = Number(ctx.detail.arousal ?? ctx.st.pulse ?? 0.4);
    ctx.st.spatialRepel = arousal > 0.45;
    V.spawn(1, { kind: 7, arousal, vy: arousal * 0.018, vx: (Math.random() - 0.5) * arousal * 0.02, decay: 0.013 });
    V.css("--face-arousal-repel", (arousal * 0.65).toFixed(3));,
  });

  V.register(8, "event ts decay", (ctx) => {
    const ts = Number(ctx.detail.ts ?? ctx.detail.raw?.ts ?? Date.now());
    const age = Math.min(1, (Date.now() - ts) / 6000);
    ctx.st.lastEventAt = ts;
    V.css("--face-event-decay", (1 - age).toFixed(3));
    V.spawn(0, { kind: 8, confidence: 1 - age, decay: 0.02 + age * 0.01 });,
  });

  V.register(9, "zone bitmask", (ctx) => {
    const mask = Number(ctx.detail.zoneMask ?? ctx.detail.zone ?? 0);
    const bits = mask > 0 ? mask : (ctx.st.zoneMask || 7);
    ctx.st.zoneMask = bits;
    document.documentElement.dataset.zoneMask = String(bits);
    V.spawn(bits & 1 ? 1 : 2, { kind: 9, zone: bits & 3, attention: 0.4, decay: 0.016 });,
  });

  V.register(10, "lint needles", (ctx) => {
    document.documentElement.dataset.lintActive = "1";
    for (let n = 0; n < 4; n++) {
      V.spawn(5, { kind: 10, vy: -0.022, vx: (n - 1.5) * 0.008, valence: -0.2, confidence: 0.55, decay: 0.019 });,
    }
    window.setTimeout(() => { delete document.documentElement.dataset.lintActive; }, 900);,
  });

  V.register(11, "scan depth cap", (ctx) => {
    const depth = Math.min(6, Number(ctx.detail.depth ?? ctx.detail.raw?.depth ?? 3));
    ctx.st.scanDepth = depth;
    document.documentElement.dataset.scanDepth = String(depth);
    V.css("--face-scan-depth", depth);,
  });

  V.register(12, "error dead cells", (ctx) => {
    const kernel = V.K();
    const p = ctx.pool;
    if (kernel && p) {
      for (let i = 0; i < p.count; i++) {
        if (!p.alive[i]) continue;
        const b = i * kernel.FIELDS_PER_CELL;
        if ((p.cells[b + kernel.FIELD.confidence] || 0) < 0.22) p.alive[i] = 0;,
      },
    }
    ctx.st.mode = ctx.st.mode === "speaking" ? ctx.st.mode : "error";
    document.documentElement.dataset.errorCells = "1";
    document.body.dataset.errorInstrument = "1";,
  });

  V.register(13, "felt_state spawn", (ctx) => {
    const felt = window.MASTERFeltState?.collectFeltState?.() || "";
    if (!felt) return;
    const parts = felt.split("|");
    const arousal = parseFloat(parts[4]) || 0.4;
    const valence = parseFloat(parts[5]) || 0;
    V.spawn(2, { kind: 13, arousal, valence, confidence: parseFloat(parts[3]) || 0.7, decay: 0.015 });
    document.documentElement.dataset.feltState = felt.slice(0, 48);,
  });

  V.register(14, "topology morph", (ctx) => {
    const topo = ctx.detail.canonical_topology || ctx.detail.topology || "papua-mask";
    ctx.st.topology = topo;
    document.documentElement.dataset.masterTopology = topo;
    document.documentElement.dataset.topologyFlash = "1";
    window.setTimeout(() => { delete document.documentElement.dataset.topologyFlash; }, 120);
    window.dispatchEvent(new CustomEvent("master:topology", { detail: { id: topo, source: ctx.type } }));,
  });

  V.register(15, "provider hue", (ctx) => {
    const provider = ctx.detail.provider || ctx.detail.raw?.provider || ctx.st.modelName || "unknown";
    const accent = providerAccent(provider);
    V.css("--master-accent", accent);
    document.documentElement.dataset.providerHue = provider;
    V.spawn(2, { kind: 15, valence: 0.2, confidence: 0.75, decay: 0.017 });,
  });

  V.register(16, "token rate spawn", (ctx) => {
    const rate = Number(ctx.detail.rate ?? ctx.detail.raw?.tokens ?? 1);
    const n = Math.min(4, Math.max(1, Math.round(rate / 40)));
    for (let i = 0; i < n; i++) {
      V.spawn(3, { kind: 16, vx: 0.01 + i * 0.003, confidence: 0.62, decay: 0.02 });,
    }
    ctx.st.tokenBurst = (ctx.st.tokenBurst || 0) + n;,
  });

  V.register(17, "tool tracers", (ctx) => {
    const tool = String(ctx.detail.tool || ctx.detail.mode || ctx.type).slice(0, 20);
    document.documentElement.dataset.activeTool = tool;
    V.spawn(4, { kind: 17, attention: 0.7, vx: 0.016, vy: -0.008, decay: 0.018 });
    window.dispatchEvent(new CustomEvent("face:tool-tracer", { detail: { tool } }));,
  });

  V.register(18, "council braids", (ctx) => {
    const persona = ctx.detail.persona || ctx.detail.raw?.persona || "council";
    for (let n = 0; n < 2; n++) {
      V.spawn(3, { kind: 18, vx: n ? 0.012 : -0.012, vy: 0.006, arousal: 0.48, decay: 0.017 });,
    }
    document.documentElement.dataset.councilBraid = String(persona).slice(0, 16);,
  });

  V.register(19, "memo freeze", (ctx) => {
    ctx.st.memoFrozen = true;
    ctx.st.decayScale = 0.35;
    document.documentElement.dataset.memoFreeze = "1";
    V.css("--face-decay-scale", "0.35");
    window.setTimeout(() => {
      ctx.st.memoFrozen = false;
      delete document.documentElement.dataset.memoFreeze;,
    }, 1400);,
  });

  V.register(20, "prune cull", (ctx) => {
    const kernel = V.K();
    if (kernel?.compact && ctx.pool) kernel.compact(ctx.pool);
    ctx.st.pruneCull = (ctx.st.pruneCull || 0) + 1;
    document.documentElement.dataset.pruneCull = String(ctx.st.pruneCull);
    V.spawn(0, { kind: 20, confidence: 0.4, decay: 0.025 });,
  });

  // 21–35 TTS
  V.register(21, "viseme lip corners", (ctx) => {
    const shape = ctx.detail.shape || ctx.st.viseme || "neutral";
    const amp = Number(ctx.detail.amp ?? ctx.st.visemeAmp ?? 0.5);
    const wide = (VISEME_CORNERS[shape] ?? 0.12) * amp;
    blend()?.pushBlend?.({ mouthWide: wide, mouthRound: Math.max(0, 0.35 - wide) });
    V.spawn(1, { kind: 21, zone: 1, valence: wide * 0.5, arousal: amp * 0.7, decay: 0.014 });,
  });

  V.register(22, "inhale 200ms", (ctx) => {
    document.documentElement.dataset.ttsInhale = "1";
    window.MASTER_FACE_PARTICLES?.anticipateSpeech?.(ctx.pool, 2);
    ctx.st.pulse = Math.max(ctx.st.pulse || 0, 0.32);
    window.setTimeout(() => { delete document.documentElement.dataset.ttsInhale; }, 200);,
  });

  V.register(23, "post-speech decay by style", (ctx) => {
    const style = ctx.detail.style || ctx.st.currentSpeechStyle || "calm";
    const decay = STYLE_DECAY[style] ?? Number(ctx.detail.decay_rate) ?? 0.85;
    blend()?.resetMouth?.(decay);
    ctx.st.pulse = Math.max(0, (ctx.st.pulse || 0) * decay);
    V.css("--face-tts-decay", decay.toFixed(3));,
  });

  V.register(24, "RMS density", (ctx) => {
    const rms = Number(ctx.detail.rms ?? ctx.detail.amp ?? ctx.st.visemeAmp ?? 0.4);
    const n = Math.min(5, Math.max(1, Math.round(rms * 4)));
    for (let i = 0; i < n; i++) {
      V.spawn(1, { kind: 24, zone: 1, arousal: rms, confidence: 0.55 + rms * 0.3, decay: 0.013 });,
    }
    document.body.dataset.ttsWave = "1";,
  });

  V.register(25, "pitch spray", (ctx) => {
    const pitch = Number(ctx.detail.pitch ?? ctx.detail.raw?.pitch ?? 0);
    const spray = Math.min(1, Math.abs(pitch) / 80);
    for (let n = 0; n < 1 + Math.round(spray * 2); n++) {
      V.spawn(1, { kind: 25, vy: pitch > 0 ? 0.014 : -0.014, vx: (Math.random() - 0.5) * spray * 0.02, decay: 0.012 });,
    }
    V.css("--face-pitch-spray", spray.toFixed(3));,
  });

  V.register(26, "word-boundary bursts", (ctx) => {
    const frames = ctx.detail.frames || ctx.detail.visemes || [];
    const count = Array.isArray(frames) ? Math.min(frames.length, 6) : 1;
    for (let i = 0; i < count; i++) {
      V.spawn(1, { kind: 26, zone: 1, arousal: 0.5, vx: (i % 2 ? 1 : -1) * 0.01, decay: 0.016 });,
    }
    document.documentElement.dataset.wordBurst = String(count);,
  });

  V.register(27, "queue lip band", (ctx) => {
    const depth = Number(ctx.detail.depth ?? ctx.detail.queue ?? 0);
    const ui = document.querySelector(".ui-status");
    if (ui && depth > 1) ui.dataset.ttsQueue = String(depth);
    else if (ui) delete ui.dataset.ttsQueue;
    V.css("--face-lip-band", Math.min(1, depth / 5).toFixed(3));
    document.documentElement.dataset.ttsQueueBand = depth > 0 ? "1" : "";,
  });

  V.register(28, "browser TTS viseme synth", (ctx) => {
    const synth = window.speechSynthesis;
    if (!synth) return;
    const shape = ctx.detail.shape || "neutral";
    document.documentElement.dataset.browserTts = synth.speaking ? "active" : "idle";
    window.dispatchEvent(new CustomEvent("tts:viseme", { detail: { shape, amp: 0.6, source: "browser" } }));,
  });

  V.register(29, "synthesizing shimmer", (ctx) => {
    document.documentElement.dataset.ttsSynth = "1";
    V.css("--face-tts-shimmer", "0.42");
    ctx.st.pulse = Math.max(ctx.st.pulse || 0, 0.25);
    window.setTimeout(() => {
      delete document.documentElement.dataset.ttsSynth;
      V.css("--face-tts-shimmer", "0");,
    }, 600);,
  });

  V.register(30, "partial TTS fill", (ctx) => {
    const partial = String(ctx.detail.text || ctx.detail.partial || "").slice(0, 40);
    if (!partial) return;
    document.documentElement.dataset.ttsPartial = partial;
    V.spawn(1, { kind: 30, zone: 1, confidence: 0.5, attention: 0.55, decay: 0.02 });,
  });

  V.register(31, "multilingual tables", (ctx) => {
    const locale = String(ctx.detail.locale || ctx.detail.raw?.locale || navigator.language || "en").slice(0, 8);
    document.documentElement.dataset.ttsLocale = locale;
    document.documentElement.lang = locale.split("-")[0];
    V.css("--face-locale-hue", locale.startsWith("en") ? "0.02" : "0.12");,
  });

  V.register(32, "whispered grain", (ctx) => {
    const style = String(ctx.detail.style || "");
    if (!/whisper|ethereal|intimate/i.test(style)) return;
    V.css("--face-whisper-grain", "0.18");
    V.spawn(1, { kind: 32, zone: 1, arousal: 0.22, confidence: 0.45, decay: 0.01 });
    document.documentElement.dataset.whisperGrain = "1";,
  });

  V.register(33, "council duo vortices", (ctx) => {
    V.spawn(3, { kind: 33, vx: -0.015, vy: 0.01, arousal: 0.5, decay: 0.015 });
    V.spawn(3, { kind: 33, vx: 0.015, vy: -0.01, arousal: 0.5, decay: 0.015 });
    document.documentElement.dataset.councilDuo = "1";,
  });

  V.register(34, "STT inward flow", (ctx) => {
    ctx.st.mode = "listening";
    for (let n = 0; n < 3; n++) {
      V.spawn(2, { kind: 34, vx: -0.008, vy: 0.004, attention: 0.65, decay: 0.017 });,
    }
    document.documentElement.dataset.sttFlow = "inward";
    document.body.dataset.masterState = "listening";,
  });

  V.register(35, "TTS error invert", (ctx) => {
    ctx.st.viseme = "neutral";
    ctx.st.visemeAmp = 0;
    V.css("--face-valence-tint", "rgba(200,80,80,0.22)");
    document.documentElement.dataset.ttsError = "1";
    blend()?.pushBlend?.({ frown: 0.35, smile: 0 });
    window.dispatchEvent(new CustomEvent("face:tts-error", { detail: ctx.detail }));,
  });

  // 36–40 fusion
  V.register(36, "compositor hint", (ctx) => {
    const hint = window.FACE3D_ACTIVE ? "face3d" : "particle2d";
    document.documentElement.dataset.compositor = hint;
    V.css("--face-compositor", hint === "face3d" ? "1" : "0");
    window.dispatchEvent(new CustomEvent("face:compositor", { detail: { hint } }));,
  });

  V.register(37, "bootBoost sync", (ctx) => {
    const ms = Number(ctx.detail.faceBootMs ?? V.impl.faceBootMs ?? 0);
    const boost = ms > 0 ? Math.max(0.4, 1 - ms / 8000) : 1;
    V.css("--face-boot-boost", boost.toFixed(3));
    document.documentElement.dataset.bootBoost = boost.toFixed(2);
    blend()?.boostEye?.(0.08);,
  });

  V.register(38, "blendshape dual-write", (ctx) => {
    const ex = ctx.detail.expression || ctx.detail;
    if (ex.arousal != null || ex.valence != null) blend()?.applyExpression?.(ex);
    if (ctx.detail.blendshapes && window.Face3DPreview?.engine?.setBlend) {
      window.Face3DPreview.engine.setBlend(ctx.detail.blendshapes);,
    }
    window.dispatchEvent(new CustomEvent("face:blend-dual", { detail: ex }));,
  });

  V.register(39, "phosphor layer split", (ctx) => {
    const speaking = ctx.st.mode === "speaking";
    document.documentElement.dataset.phosphorSplit = speaking ? "mouth" : "face";
    V.css("--face-phosphor-decay", speaking ? "0.68" : "0.82");
    if (window.MASTER_PHOSPHOR_TRAIL) document.documentElement.dataset.phosphorActive = "1";,
  });

  V.register(40, "primer preview", (ctx) => {
    document.documentElement.dataset.primerPreview = "1";
    V.spawn(2, { kind: 40, attention: 0.8, confidence: 0.85, arousal: 0.35, decay: 0.012 });
    blend()?.boostEye?.(0.1);
    V.css("--face-primer-glow", "0.28");
    window.dispatchEvent(new CustomEvent("face:primer-preview", { detail: { ts: performance.now() } }));,
  });,
})();
