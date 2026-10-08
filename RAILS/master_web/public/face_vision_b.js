// MASTER particle face 2026 — vision features 41–80 (fusion, SSE cinema, perf).
(() => {
  "use strict";

  const V = window.MASTER_FACE_VISION;
  if (!V) return;

  const root = document.documentElement;
  const body = document.body;
  const qs = (k) => new URLSearchParams(location.search).get(k);

  function emit(type, detail = {}) {
    window.MASTERVisual?.event?.(type, detail);
  }

  /* 41–50 fusion */
  V.register(41, "morph easing", (ctx) => {
    const ease = (t) => 1 - Math.pow(1 - Math.min(1, Math.max(0, t)), 3);
    const tgt = ctx.st.morphTarget ?? 1;
    if (ctx.st.morphEase == null) ctx.st.morphEase = tgt;
    const alpha = ease(0.08);
    ctx.st.morphEase += (tgt - ctx.st.morphEase) * alpha;
    V.css("--face-morph-ease", ctx.st.morphEase.toFixed(3));
    root.dataset.morphEasing = "cubic-out";
  });

  V.register(42, "OLED black", (ctx) => {
    const oled = root.dataset.runtimeProfile === "battery"
      || qs("oled") === "1"
      || window.matchMedia?.("(dynamic-range: high)")?.matches;
    root.dataset.oledBlack = oled ? "1" : "";
    if (oled) {
      body.style.backgroundColor = "#000";
      V.css("--face-bg", "#000");
    }
    V.spawn(0, { kind: 42, confidence: oled ? 0.9 : 0.5, decay: 0.02 });
  });

  V.register(43, "CRT block", (ctx) => {
    const crt = root.dataset.runtimeProfile === "crt" || qs("crt") === "1";
    root.dataset.crtBlock = crt ? "1" : "";
    V.css("--face-scanline", crt ? "0.42" : "0.12");
    if (crt) V.spawn(2, { kind: 43, vy: 0.008, confidence: 0.7, decay: 0.018 });
  });

  V.register(44, "battery cap", (ctx) => {
    const battery = root.dataset.runtimeProfile === "battery" || ctx.st.coarsePointer;
    if (battery) {
      const cap = Math.floor((navigator.hardwareConcurrency || 4) * 120);
      ctx.st.particleCap = cap;
      root.dataset.batteryCap = String(cap);
      V.css("--face-particle-cap", cap);
    }
  });

  V.register(45, "pip mode", (ctx) => {
    const pip = body.classList.contains("face-pip") || ctx.detail.pip;
    root.dataset.pipMode = pip ? "1" : "";
    if (pip) V.css("--face-pip-scale", "0.38");
  });

  V.register(46, "LOD metaballs", (ctx) => {
    const fps = ctx.st.fps || 60;
    const lod = fps < 28 ? 0.45 : fps < 45 ? 0.72 : 1;
    ctx.st.metaballLod = lod;
    root.dataset.metaballLod = lod.toFixed(2);
    V.css("--face-metaball-lod", lod.toFixed(2));
  });

  V.register(47, "logo dim", () => {
    const logo = document.querySelector(".top-left-logo");
    if (!logo) return;
    logo.classList.add("dim");
    root.dataset.logoDim = "1";
  });

  V.register(48, "council badge pulse", (ctx) => {
    const badge = document.getElementById("council-persona-badge");
    if (!badge) return;
    const persona = ctx.detail.persona || ctx.detail.raw?.persona || "council";
    badge.textContent = String(persona).slice(0, 18);
    badge.dataset.visible = "1";
    badge.dataset.pulse = "1";
    window.setTimeout(() => {
      badge.dataset.pulse = "";
      badge.dataset.visible = "0";
    }, 900);
  });

  V.register(49, "violation shockwave", (ctx) => {
    ctx.st.flash = 1;
    ctx.st.shake = Math.max(ctx.st.shake || 0, 0.9);
    ctx.st.ripplePhase = (ctx.st.ripplePhase || 0) + 1;
    root.dataset.violationShock = String(Date.now());
    for (let n = 0; n < 5; n++) {
      V.spawn(4, { kind: 49, vx: (n - 2) * 0.02, vy: 0.012, arousal: 0.8, decay: 0.01 });
    }
    emit("violation:shockwave", { topology: "serpent", entropy: 0.92, confidence: 0.15, mode: "violation" });
  });

  V.register(50, "sleeping dim", (ctx) => {
    const sleeping = ctx.st.sleeping || ctx.st.mode === "sleeping";
    root.dataset.sleepingDim = sleeping ? "1" : "";
    if (sleeping) {
      body.style.opacity = "0.05";
      V.css("--face-sleep-opacity", "0.05");
    } else if (body.style.opacity === "0.05") {
      body.style.opacity = "";
      V.css("--face-sleep-opacity", "1");
    }
  });

  /* 51–65 SSE cinema */
  V.register(51, "visual grammar flag", () => {
    root.dataset.visualGrammar = "sse-v2";
    root.dataset.visualGrammarReady = "1";
  });

  V.register(52, "SSE backpressure priority", (ctx) => {
    const PRIORITY = ["verdict", "stage", "felt", "thought", "dmesg", "tool", "enhance"];
    const name = String(ctx.type || "").split(":").pop();
    const idx = PRIORITY.indexOf(name);
    ctx.st.ssePriority = idx < 0 ? 99 : idx;
    root.dataset.sseBackpressure = "priority-queue";
    V.css("--sse-priority", ctx.st.ssePriority);
  });

  V.register(53, "council rotator overlay", (ctx) => {
    let rot = document.getElementById("council-rotator-overlay");
    if (!rot) {
      rot = document.createElement("div");
      rot.id = "council-rotator-overlay";
      rot.className = "council-rotator-overlay";
      rot.setAttribute("aria-hidden", "true");
      body.appendChild(rot);
    }
    const p = ctx.detail.persona || ctx.detail.raw?.persona || ctx.detail.mode || "council";
    rot.textContent = String(p).slice(0, 48);
    rot.dataset.visible = "1";
    window.setTimeout(() => { rot.dataset.visible = "0"; }, 2400);
  });

  V.register(54, "codebase graph layout", (ctx) => {
    const topo = ctx.detail.topology || "neural";
    root.dataset.codebaseGraph = "force-directed";
    root.dataset.graphLayout = topo;
    V.spawn(4, { kind: 54, attention: 0.6, vx: 0.01, decay: 0.02 });
  });

  V.register(55, "scheduler ripple", (ctx) => {
    ctx.st.ripplePhase = (ctx.st.ripplePhase || 0) + 0.35;
    root.dataset.schedulerRipple = String(performance.now() | 0);
    V.css("--scheduler-ripple", ctx.st.ripplePhase.toFixed(2));
    V.spawn(2, { kind: 55, vy: 0.01, confidence: 0.65, decay: 0.017 });
  });

  V.register(56, "face-stage ASCII", (ctx) => {
    let strip = document.getElementById("face-stage-ascii");
    if (!strip) {
      strip = document.createElement("pre");
      strip.id = "face-stage-ascii";
      strip.className = "face-stage-ascii";
      strip.setAttribute("aria-hidden", "true");
      body.appendChild(strip);
    }
    const FRAMES = ["(◉_◉)", "(◔_◔)", "(◕‿◕)", "(⌐■_■)", "(•̀ᴗ•́)"];
    const stage = String(ctx.detail.stage || ctx.type || "…");
    strip.textContent = `${FRAMES[Math.floor(Math.random() * FRAMES.length)]} ${stage}`;
  });

  V.register(57, "smoke heartbeat", () => {
    root.dataset.smokeHeartbeat = root.dataset.smokeHeartbeat === "on" ? "off" : "on";
    V.spawn(0, { kind: 57, arousal: 0.3, decay: 0.025 });
  });

  V.register(58, "429 stutter", (ctx) => {
    ctx.st.shake = Math.max(ctx.st.shake || 0, 0.4);
    root.dataset.stutter429 = "1";
    V.css("--face-stutter", "0.4");
    window.setTimeout(() => {
      delete root.dataset.stutter429;
      V.css("--face-stutter", "0");
    }, 600);
  });

  V.register(59, "visitor tier kinds", (ctx) => {
    const tier = ctx.detail.tier
      || window.MASTER_RUNTIME?.visitor_tier
      || window.MASTER_RUNTIME?.tier
      || qs("tier")
      || "guest";
    root.dataset.visitorTier = String(tier);
    body.dataset.visitorTier = String(tier);
  });

  V.register(60, "elevated gold edge", (ctx) => {
    const elevated = root.dataset.visitorTier === "elevated"
      || root.dataset.visitorTier === "operator"
      || qs("elevated") === "1";
    if (elevated) {
      root.dataset.goldEdge = "1";
      V.css("--face-edge-gold", "1");
      V.spawn(2, { kind: 60, valence: 0.4, confidence: 0.85, decay: 0.016 });
    }
  });

  V.register(61, "token entropy nudge", (ctx) => {
    ctx.st.streamTokens = (ctx.st.streamTokens || 0) + 1;
    ctx.st.entropy = Math.min(1, (ctx.st.entropy ?? 0.2) + 0.002);
    if (ctx.st.streamTokens % 40 === 0) {
      emit("token:entropy", { topology: "terrain", entropy: ctx.st.entropy, confidence: ctx.st.confidence || 0.7, mode: "stream" });
    }
    V.spawn(3, { kind: 61, confidence: ctx.st.entropy, decay: 0.02 });
  });

  V.register(62, "DONE archive spiral", (ctx) => {
    ctx.st.spiralPhase = (ctx.st.spiralPhase || 0) + 1.2;
    root.dataset.archiveSpiral = String(ctx.st.spiralPhase);
    V.css("--archive-spiral", ctx.st.spiralPhase.toFixed(2));
    V.spawn(3, { kind: 62, vx: Math.sin(ctx.st.spiralPhase) * 0.02, vy: Math.cos(ctx.st.spiralPhase) * 0.02, decay: 0.015 });
  });

  V.register(63, "replay scrub hook", (ctx) => {
    const t = Math.max(0, Number(ctx.detail.t ?? ctx.detail.scrub ?? 0));
    root.dataset.replayScrub = String(t);
    emit("replay:scrub", { topology: "warp-tunnel", entropy: 0.3, confidence: 0.8, mode: "replay", t });
    V.css("--replay-scrub", t.toFixed(2));
  });

  V.register(64, "why branching trees", (ctx) => {
    root.dataset.whyTree = ctx.detail.topology || "branch";
    V.spawn(4, { kind: 64, vx: 0.012, vy: -0.006, attention: 0.55, decay: 0.019 });
    emit("why:branch", { topology: "neural", entropy: 0.28, confidence: 0.75, mode: "why", node: ctx.detail.node });
  });

  V.register(65, "metrics HUD", (ctx) => {
// Opt-in. This read `qs("hud") === "0"`, so fps, mode and entropy rendered
// full-width at the top of the surface for every visitor unless they knew
// to ask for silence. It is diagnostics — the element carries
// aria-hidden="true", which is the code already saying it is not content —
// and a console surface earns its calm by not showing its own frame rate.
// ?hud=1 brings it back.
if (qs("hud") !== "1") return;
    let hud = document.getElementById("face-metrics-hud");
    if (!hud) {
      hud = document.createElement("div");
      hud.id = "face-metrics-hud";
      hud.className = "face-metrics-hud";
      hud.setAttribute("aria-hidden", "true");
      body.appendChild(hud);
    }
    const fps = ctx.st.fps ? ctx.st.fps.toFixed(0) : "—";
    const mode = ctx.st.mode || "idle";
    const ent = (ctx.st.entropy ?? 0.2).toFixed(2);
    hud.textContent = `fps ${fps} · ${mode} · H ${ent}`;
  });

  /* 66–80 perf */
  V.register(66, "worker owns step flag", () => {
    const owns = !!(window.MASTER_RUNTIME?.enhancements?.includes?.("particle_worker") && window.Worker);
    root.dataset.workerOwnsStep = owns ? "1" : "";
  });

  V.register(67, "WebGPU stub detect", (ctx) => {
    const supported = !!ctx.detail.webgpu;
    root.dataset.webgpu = supported ? "ready" : "stub";
    root.dataset.webgpuStub = supported ? "" : "1";
  });

  V.register(68, "adaptive pool cap from hardwareConcurrency/deviceMemory", (ctx) => {
    const cores = navigator.hardwareConcurrency || 4;
    const mem = navigator.deviceMemory || 4;
    const cap = Math.min(8192, Math.max(512, cores * 160 * Math.min(2, mem / 4)));
    ctx.st.poolCap = cap | 0;
    root.dataset.poolCap = String(cap | 0);
    V.css("--face-pool-cap", cap | 0);
  });

  V.register(69, "compact on hidden+tts end", (ctx) => {
    const tts = window.MASTER_FACE?.tts;
    if (document.hidden && tts && !tts.playing) {
      root.dataset.compactHidden = "1";
      emit("compaction:done", { topology: "terrain", entropy: 0.35, confidence: 0.7, mode: "compact" });
      V.K()?.compact?.(ctx.pool);
    } else {
      delete root.dataset.compactHidden;
    }
  });

  V.register(70, "double-buffer flag", () => {
    const dbl = typeof OffscreenCanvas !== "undefined" || qs("dblbuf") === "1";
    root.dataset.doubleBuffer = dbl ? "1" : "";
  });

  V.register(71, "WASM stub", () => {
    const wasm = typeof WebAssembly !== "undefined";
    root.dataset.wasm = wasm ? "available" : "stub";
    root.dataset.wasmStub = wasm ? "" : "1";
  });

  V.register(72, "luminance cull", (ctx) => {
    root.dataset.luminanceCull = "0.04";
    const kernel = V.K();
    const p = ctx.pool;
    if (!kernel || !p) return;
    for (let i = 0; i < p.count; i++) {
      if (!p.alive[i]) continue;
      const b = i * kernel.FIELDS_PER_CELL;
      const r = p.cells[b] || 0;
      const g = p.cells[b + 1] || 0;
      const bl = p.cells[b + 2] || 0;
      const lum = 0.2126 * r + 0.7152 * g + 0.0722 * bl;
      if (lum < 0.04) p.alive[i] = 0;
    }
  });

  V.register(73, "audio sync step", (ctx) => {
    const tts = window.MASTER_FACE?.tts;
    if (!tts?.playing || !tts.audio) return;
    const t = tts.audio.currentTime || 0;
    ctx.st.audioSyncStep = Math.sin(t * 12) * 0.02;
    V.css("--audio-sync-step", ctx.st.audioSyncStep.toFixed(4));
  });

  V.register(74, "rvfc TV hook", (ctx) => {
    const t = Number(ctx.detail.frame ?? ctx.detail.t ?? 0);
    root.dataset.rvfcTv = t ? String(t | 0) : "stub";
    ctx.st.tvFrame = t;
  });

  V.register(75, "prewarm worker on primer", () => {
    if (!window.MASTER_RUNTIME?.enhancements?.includes?.("particle_worker")) return;
    try {
      const url = window.MASTER_ASSET_PATHS?.faceModules?.particle_worker || "/particle_worker.js";
      const worker = new Worker(url);
      worker.postMessage({ type: "warm", dt: 0.016 });
      window.setTimeout(() => worker.terminate(), 120);
      root.dataset.workerPrewarm = "1";
    } catch (err) {
      window.MASTER_LOG?.warn?.("vision:worker-prewarm", err);
    }
  });

  V.register(76, "static import flag", () => {
    const statik = !!(window.MASTER_ASSET_PATHS?.faceModulesBundle || window.MASTER_FACE);
    root.dataset.staticImport = statik ? "1" : "";
  });

  V.register(77, "RAF governor hook", (ctx) => {
    const throttle = root.dataset.thermalThrottle === "0.5";
    const min = throttle ? 33 : 16;
    const now = performance.now();
    if (!ctx.st._rafLast) ctx.st._rafLast = 0;
    const ok = now - ctx.st._rafLast >= min;
    if (ok) ctx.st._rafLast = now;
    root.dataset.rafGovernor = ok ? "tick" : "skip";
    ctx.st.rafGovernorOk = ok;
  });

  V.register(78, "thermal throttle 50%", (ctx) => {
    const throttle = !!ctx.detail.throttle;
    root.dataset.thermalThrottle = throttle ? "0.5" : "0";
    if (throttle) ctx.st.particlePressure = 0.5;
    V.css("--thermal-throttle", throttle ? "0.5" : "1");
  });

  V.register(79, "bench mode ?bench=1", (ctx) => {
    if (qs("bench") !== "1") return;
    root.dataset.benchMode = "1";
    body.dataset.bench = "1";
    const fps = Number(ctx.detail.fps ?? ctx.st.benchFps ?? 0);
    if (fps > 0) {
      root.dataset.benchFps = fps.toFixed(1);
      try {
        localStorage.setItem("master:bench:last", JSON.stringify({ fps, at: Date.now() }));
      } catch (err) { window.MASTER_LOG?.warn?.("face_vision_b:bench_store", err); }
    }
  });

  V.register(80, "Cache-Control note via dataset", () => {
    const ver = window.MASTER_CACHE_VERSION || "v2";
    root.dataset.cacheControl = `immutable; v=${ver}`;
    root.dataset.masterCacheVersion = String(ver);
  });

  /* wiring — init listeners + one-shot probes */
  (function wireVisionB() {
    V.run(80, { type: "init", detail: {} });
    V.run(51, { type: "init", detail: {} });
    V.run(59, { type: "init", detail: {} });
    V.run(66, { type: "init", detail: {} });
    V.run(68, { type: "init", detail: {} });
    V.run(70, { type: "init", detail: {} });
    V.run(71, { type: "init", detail: {} });
    V.run(76, { type: "init", detail: {} });

    if (navigator.gpu?.requestAdapter) {
      navigator.gpu.requestAdapter().then((a) => {
        V.run(67, { type: "webgpu:probe", detail: { webgpu: !!a } });
      }).catch(() => V.run(67, { type: "webgpu:probe", detail: { webgpu: false } }));
    } else {
      V.run(67, { type: "webgpu:probe", detail: { webgpu: false } });
    }

    const logo = document.querySelector(".top-left-logo");
    if (logo) {
      let timer = null;
      const sched = () => {
        window.clearTimeout(timer);
        timer = window.setTimeout(() => V.run(47, { type: "logo:idle", detail: {} }), 4000);
      };
      sched();
      document.addEventListener("pointerdown", () => {
        logo.classList.remove("dim");
        delete root.dataset.logoDim;
        sched();
      }, { passive: true });
    }

    const cv = document.getElementById("face") || document.getElementById("mask");
    if (cv) {
      cv.addEventListener("keydown", (e) => {
        if (e.altKey && e.key === "p") {
          body.classList.toggle("face-pip");
          V.run(45, { type: "pip:toggle", detail: { pip: body.classList.contains("face-pip") } });
        }
      });
    }

    window.addEventListener("master:self_violation", () => {
      V.run(49, { type: "master:self_violation", detail: {} });
    });

    window.addEventListener("master:face-stage", (ev) => {
      V.run(56, { type: "master:face-stage", detail: ev.detail || {} });
    });

    window.addEventListener("master:visual", (ev) => {
      const d = ev.detail || {};
      const name = String(d.name || d.mode || "");
      V.run(41, { type: name, detail: d });
      V.run(50, { type: name, detail: d });
      V.run(65, { type: name, detail: d });
      V.run(73, { type: name, detail: d });
      V.run(77, { type: name, detail: d });
      if (/council/i.test(name)) {
        V.run(48, { type: name, detail: d });
        V.run(53, { type: name, detail: d });
      }
      if (/stage|scheduler|pipeline/i.test(name)) V.run(55, { type: name, detail: d });
      if (/scan|graph|codebase/i.test(name)) V.run(54, { type: name, detail: d });
      if (/done|archive|complete/i.test(name)) V.run(62, { type: name, detail: d });
      if (/why|propose-tree/i.test(name)) V.run(64, { type: name, detail: d });
      if (/429|rate.?limit/i.test(name)) V.run(58, { type: name, detail: d });
      if (/replay|scrub/i.test(name)) V.run(63, { type: name, detail: d });
      V.run(52, { type: name, detail: d });
      V.run(60, { type: name, detail: d });
    });

    window.addEventListener("chat:chunk", () => V.run(61, { type: "chat:chunk", detail: {} }));
    window.addEventListener("chat:error", () => V.run(58, { type: "chat:error", detail: {} }));

    document.addEventListener("visibilitychange", () => {
      V.run(69, { type: "visibilitychange", detail: {} });
    }, { passive: true });

    window.addEventListener("primer:ready", () => V.run(75, { type: "primer:ready", detail: {} }));

    const video = document.querySelector("video[data-face-tv], #face-tv");
    if (video?.requestVideoFrameCallback) {
      const loop = () => {
        video.requestVideoFrameCallback((now) => {
          V.run(74, { type: "rvfc", detail: { frame: now } });
          loop();
        });
      };
      video.addEventListener("play", loop, { once: true });
      root.dataset.rvfcTv = "hooked";
    }

    if ("PressureObserver" in window) {
      try {
        const obs = new PressureObserver((records) => {
          const serious = records.some((r) => r.state === "serious" || r.state === "critical");
          V.run(78, { type: "pressure", detail: { throttle: serious } });
        }, { sampleRate: 0.5 });
        obs.observe("cpu").catch(() => {});
      } catch (_) {
        root.dataset.thermalThrottle = "stub";
      }
    }

    if (qs("bench") === "1") {
      const t0 = performance.now();
      let frames = 0;
      const loop = () => {
        frames++;
        V.run(46, { type: "bench:tick", detail: {}, st: V.state() });
        if (performance.now() - t0 >= 3000) {
          V.run(79, { type: "bench:done", detail: { fps: frames / 3 } });
          return;
        }
        requestAnimationFrame(loop);
      };
      requestAnimationFrame(loop);
    }

    window.setInterval(() => V.run(57, { type: "heartbeat", detail: {} }), 8000);
    window.setInterval(() => {
      const st = V.state();
      st.fps = st.fps || 60;
      V.run(46, { type: "fps:tick", detail: {} });
      V.run(72, { type: "cull:tick", detail: {}, pool: V.pool() });
    }, 1000);
  })();
})();
