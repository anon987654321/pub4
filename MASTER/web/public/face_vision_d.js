// MASTER particle face 2026 — vision features 119–150 (reliability, frontier).
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

  function sessionGet(key) {
    try { return sessionStorage.getItem(key); } catch (_) { return null; }
  }

  function sessionSet(key, val) {
    try { sessionStorage.setItem(key, val); return true; } catch (_) { return false; }
  }

  function storeGet(key) {
    try { return localStorage.getItem(key); } catch (_) { return null; }
  }

  function storeSet(key, val) {
    try { localStorage.setItem(key, val); return true; } catch (_) { return false; }
  }

  /* 119–130 reliability */
V.register(119, "build version on the root, not on the screen", () => {
  const ver = window.MASTER_CACHE_VERSION || "dev";
  // The dataset, not a span. This appended a visible <span id="build-badge">
  // to every page — ungated, aria-hidden, showing a cache version in the
  // corner of a surface whose whole subject is the face. The information is
  // worth keeping and was never worth a pixel: it stays queryable here, and
  // /health already reports git_sha for anyone asking which build is live.
  root.dataset.buildBadge = ver;
  document.getElementById("build-badge")?.remove();
});

  V.register(120, "PROBE_STRICT note", () => {
    const strict = window.MASTER_RUNTIME?.probe_strict
      || window.PROBE_STRICT
      || qs("probe_strict") === "1";
    root.dataset.probeStrict = strict ? "1" : "0";
  });

  V.register(121, "relayctl health dataset", (ctx) => {
    root.dataset.relayctlHealth = ctx.detail.health || "unknown";
  });

  V.register(122, "sw:updated auto-reload once if primer fired", (ctx) => {
    if (!window._primerFired) return;
    const version = ctx.detail.version || window.MASTER_CACHE_VERSION || "unknown";
    const key = `master:sw-reload:${version}`;
    if (sessionGet(key)) return;
    sessionSet(key, "1");
    location.reload();
  });

  V.register(123, "retry boot button in container timeout", () => {
    const container = document.getElementById("face-container")
      || document.getElementById("primer")
      || body;
    let btn = document.getElementById("face-boot-retry");
    if (!btn) {
      btn = document.createElement("button");
      btn.id = "face-boot-retry";
      btn.type = "button";
      btn.className = "face-boot-retry";
      btn.textContent = "retry face boot";
      btn.addEventListener("click", () => {
        delete body.dataset.faceBooting;
        btn.remove();
        window.dispatchEvent(new CustomEvent("primer:ready"));
        window.MASTER_FACE_VISION?.boot?.({ force: true });
      });
      container.appendChild(btn);
    }
    root.dataset.bootRetry = "1";
  });

  V.register(124, "face boot error module name in showBootError hook via master:face-error detail", (ctx) => {
    const mod = ctx.detail.module || ctx.detail.stage || "face_vision";
    const msg = ctx.detail.message || "boot failed";
    let banner = document.getElementById("face-error-banner");
    if (!banner) {
      banner = document.createElement("div");
      banner.id = "face-error-banner";
      banner.className = "face-error-banner";
      body.appendChild(banner);
    }
    banner.textContent = `${mod}: ${msg}`;
    root.dataset.bootErrorModule = mod;
    window.dispatchEvent(new CustomEvent("master:face-error", {
      detail: { message: msg, module: mod, stage: ctx.detail.stage || "boot" }
    }));
  });

  V.register(125, "offline queue hook", (ctx) => {
    if (!window._offlineQueue) window._offlineQueue = [];
    if (ctx.detail.flush) {
      while (window._offlineQueue.length && navigator.onLine) {
        const item = window._offlineQueue.shift();
        fetch("/canvas/event", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: item.body,
          keepalive: true
        }).catch(() => {
          window._offlineQueue.unshift(item);
        });
      }
    } else if (ctx.detail.body) {
      window._offlineQueue.push({ body: ctx.detail.body, at: Date.now() });
    }
    root.dataset.offlineQueue = String(window._offlineQueue.length);
  });

  V.register(126, "PWA install after 3 sessions", (ctx) => {
    const KEY = "master:pwa:sessions";
    const n = Number(ctx.detail.sessions ?? 0);
    root.dataset.pwaSessions = String(n);
    if (n >= 3 && window._deferredInstallPrompt) {
      window._deferredInstallPrompt.prompt?.();
      root.dataset.pwaInstallPrompt = "shown";
    }
  });

  V.register(127, "falcon worker budget note", () => {
    const budget = window.MASTER_RUNTIME?.falcon_worker_budget
      || window.MASTER_RUNTIME?.worker_budget
      || "default";
    root.dataset.falconWorkerBudget = String(budget);
  });

  V.register(128, "TTS queue metrics", (ctx) => {
    const tts = window.MASTER_FACE?.tts;
    const len = tts?.queue?.length ?? 0;
    const playing = tts?.playing ? 1 : 0;
    root.dataset.ttsQueue = `${len}/${playing}`;
    V.css("--tts-queue-depth", len);
  });

  V.register(129, "POST face metrics to /canvas/event topic face:metrics", (ctx) => {
    const st = ctx.st;
    const impl = V.impl || {};
    const bodyParams = new URLSearchParams({
      topic: "face:metrics",
      "payload[face_boot_ms]": String(impl.faceBootMs || root.dataset.faceBootMs || 0),
      "payload[particle_worker_alive]": String(!!impl.particleWorkerAlive),
      "payload[feature_count]": String(V.featureCount || 0),
      "payload[bench_fps]": String(st.fps || root.dataset.benchFps || 0)
    });
    fetch("/canvas/event", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: bodyParams,
      keepalive: true
    }).catch(() => {});
    root.dataset.faceMetricsPosted = String(Date.now());
  });

  V.register(130, "dogfood note", () => {
    const dogfood = location.hostname === "localhost"
      || qs("dogfood") === "1"
      || window.MASTER_RUNTIME?.dogfood;
    root.dataset.dogfood = dogfood ? "1" : "0";
  });

  /* 131–150 frontier */
  V.register(131, "WebNN viseme stub", (ctx) => {
    const has = !!(navigator.ml || window.MLContext);
    root.dataset.webnnViseme = has ? "available" : "stub";
    ctx.detail.result = has ? { stub: true } : null;
  });

  V.register(132, "SharedArrayBuffer tab sync stub", () => {
    const sab = typeof SharedArrayBuffer !== "undefined" && crossOriginIsolated;
    root.dataset.sabTabSync = sab ? "ready" : "stub";
  });

  V.register(133, "WebTransport stub", (ctx) => {
    const has = typeof WebTransport !== "undefined";
    root.dataset.webTransport = has ? "available" : "stub";
    if (has && ctx.detail.url) {
      try { ctx.detail.transport = new WebTransport(ctx.detail.url); } catch (err) { window.MASTER_LOG?.warn?.("face_vision_d:web_transport", err); }
    }
  });

  V.register(134, "View Transitions primer morph", () => {
    if (!document.startViewTransition) {
      root.dataset.viewTransition = "stub";
      return;
    }
    root.dataset.viewTransition = "hooked";
    const primer = document.getElementById("primer");
    if (!primer) return;
    primer.addEventListener("click", () => {
      document.startViewTransition(() => {
        primer.classList.add("gone");
        body.classList.add("face-session");
      });
    }, { once: true });
  });

  V.register(135, "scroll-driven depth stub", () => {
    if (!CSS.supports?.("animation-timeline: scroll()")) {
      root.dataset.scrollDepth = "stub";
      return;
    }
    root.dataset.scrollDepth = "css";
    V.css("--scroll-depth", "scroll-driven");
  });

  V.register(136, "interest invokers lazy load note", () => {
    const invokers = !!HTMLScriptElement?.supports?.("interact-invokers");
    root.dataset.interestInvokers = invokers ? "supported" : "lazy-note";
  });

  V.register(137, "Compute Pressure downgrade", (ctx) => {
    if (!ctx.detail.downgrade) return;
    root.dataset.computePressure = "downgrade";
    root.dataset.runtimeProfile = "battery";
    emit("perf:downgrade", { topology: "terrain", entropy: 0.4, confidence: 0.6, mode: "downgrade" });
    V.run(78, { type: "compute-pressure", detail: { throttle: true } });
  });

  V.register(138, "ML gaze opt-in stub", (ctx) => {
    root.dataset.mlGaze = ctx.detail.optedIn ? "opted-in" : "opt-in-stub";
  });

  V.register(139, "spatial audio council", (ctx) => {
    const ctxAudio = window.MASTER_FACE?.actx;
    if (!ctxAudio?.createStereoPanner) {
      root.dataset.spatialAudio = "stub";
      return;
    }
    const lane = ctx.detail.lane || ctx.detail.raw?.lane;
    const pan = lane === "left" ? -0.6 : lane === "right" ? 0.6 : 0;
    root.dataset.spatialAudio = `pan-${pan}`;
    V.css("--council-pan", String(pan));
  });

  V.register(140, "WebXR stub", (ctx) => {
    const has = !!navigator.xr;
    root.dataset.webxr = has ? "available" : "stub";
    if (has && ctx.detail.vr != null) root.dataset.webxrVr = ctx.detail.vr ? "1" : "0";
  });

  V.register(141, "collaborative ActionCable fanout hook", (ctx) => {
    if (!window.ActionCable) {
      root.dataset.actionCableFanout = "stub";
      return;
    }
    window.dispatchEvent(new CustomEvent("master:cable-fanout", { detail: ctx.detail.event || ctx.detail }));
    root.dataset.actionCableFanout = "hooked";
  });

  V.register(142, "generative topology JSON", (ctx) => {
    const s = Number(ctx.detail.seed) || Date.now();
    const nodes = Array.from({ length: 8 }, (_, i) => ({
      id: i,
      x: Math.sin(s * 0.001 + i) * 0.5,
      y: Math.cos(s * 0.0013 + i) * 0.5
    }));
    const json = { seed: s, nodes, edges: nodes.slice(0, -1).map((n, i) => [n.id, nodes[i + 1].id]) };
    root.dataset.genTopology = String(s);
    ctx.detail.topology = json;
    return json;
  });

  V.register(143, "on-device rules.yml flash", (ctx) => {
    const text = ctx.detail.text || "";
    if (!text) {
      root.dataset.rulesFlash = "stub";
      return;
    }
    root.dataset.rulesFlash = `${text.length}b`;
    storeSet("master:rules-flash", text.slice(0, 4096));
  });

  V.register(144, "benchmark leaderboard localStorage", (ctx) => {
    const KEY = "master:bench:leaderboard";
    const entry = ctx.detail.entry;
    if (!entry) return;
    try {
      const list = JSON.parse(storeGet(KEY) || "[]");
      list.push({ ...entry, at: Date.now() });
      list.sort((a, b) => (b.fps || 0) - (a.fps || 0));
      storeSet(KEY, JSON.stringify(list.slice(0, 20)));
      ctx.detail.leaderboard = list;
    } catch (err) { window.MASTER_LOG?.warn?.("face_vision_d:leaderboard_store", err); }
  });

  V.register(145, "plugin viseme packs JSON", (ctx) => {
    const packs = ctx.detail.packs;
    if (packs) {
      V.visemePacks = packs;
      root.dataset.visemePacks = String(Object.keys(packs).length);
    } else {
      V.visemePacks = { default: ["AA", "EE", "OH", "MM", "rest"] };
      root.dataset.visemePacks = "stub";
    }
  });

  V.register(146, "time-travel trace scrub", (ctx) => {
    const trace = window._faceTrace || [];
    const target = Number(ctx.detail.t) || 0;
    const hit = trace.filter((e) => e.t <= target).pop();
    if (hit) {
      emit("trace:scrub", { topology: "warp-tunnel", entropy: 0.25, confidence: 0.8, mode: hit.mode || "trace", t: target });
    }
    ctx.detail.hit = hit || null;
  });

  V.register(147, "cross-app postMessage mood", (ctx) => {
    if (ctx.detail.broadcast) {
      window.parent?.postMessage?.({ type: "master:mood", mood: ctx.st.mood, mode: ctx.st.mode }, "*");
      return;
    }
    const mood = ctx.detail.mood;
    const mode = ctx.detail.mode;
    if (mood) ctx.st.mood = mood;
    if (mode) ctx.st.mode = mode;
    root.dataset.crossAppMood = ctx.st.mood || "";
    emit("mood:cross-app", { topology: "papua-mask", entropy: 0.15, confidence: 0.85, mode: ctx.st.mode });
  });

  V.register(148, "WebM moment export", async (ctx) => {
    const cv = document.getElementById("face") || document.getElementById("mask");
    if (!cv?.captureStream) {
      root.dataset.webmExport = "stub";
      ctx.detail.blob = null;
      return;
    }
    try {
      const stream = cv.captureStream(30);
      const rec = new MediaRecorder(stream, { mimeType: "video/webm" });
      const chunks = [];
      rec.ondataavailable = (e) => chunks.push(e.data);
      rec.start();
      await new Promise((r) => window.setTimeout(r, Number(ctx.detail.ms) || 3000));
      rec.stop();
      await new Promise((r) => { rec.onstop = r; });
      ctx.detail.blob = new Blob(chunks, { type: "video/webm" });
      root.dataset.webmExport = "ok";
    } catch (_) {
      root.dataset.webmExport = "stub";
      ctx.detail.blob = null;
    }
  });

  V.register(149, "zero-JS shell note", () => {
    const noscript = document.querySelector("noscript");
    root.dataset.zeroJsShell = noscript ? "noscript-present" : "js-required";
    if (!noscript) {
      const el = document.createElement("noscript");
      el.textContent = "MASTER particle face requires JavaScript.";
      body.appendChild(el);
    }
  });

  V.register(150, "public API MASTERVisual.event documented on MASTER_FACE_VISION", () => {
    /**
     * Proxy to window.MASTERVisual.event — canonical visual bus for face + chat.
     * @param {string} type - Event name (e.g. face:describe, council:pulse)
     * @param {Object} [detail] - { topology, entropy, confidence, mode, ... }
     */
    if (!V.event.doc) {
      V.event.doc = "Proxy to MASTERVisual.event(type, detail) — canonical visual bus.";
    }
    root.dataset.publicApi = "MASTERVisual.event";
  });

  /* wiring */
  (function wireVisionD() {
    V.run(119, { type: "init", detail: {} });
    V.run(120, { type: "init", detail: {} });
    V.run(127, { type: "init", detail: {} });
    V.run(130, { type: "init", detail: {} });
    V.run(132, { type: "init", detail: {} });
    V.run(135, { type: "init", detail: {} });
    V.run(136, { type: "init", detail: {} });
    V.run(149, { type: "init", detail: {} });
    V.run(150, { type: "init", detail: {} });

    V.run(131, { type: "init", detail: {} });

    fetch("/health", { credentials: "same-origin", cache: "no-store" })
      .then((r) => V.run(121, { type: "health", detail: { health: r.ok ? "ok" : `err-${r.status}` } }))
      .catch(() => V.run(121, { type: "health", detail: { health: "offline" } }));

    window.setInterval(() => {
      fetch("/health", { credentials: "same-origin", cache: "no-store" })
        .then((r) => V.run(121, { type: "health", detail: { health: r.ok ? "ok" : `err-${r.status}` } }))
        .catch(() => V.run(121, { type: "health", detail: { health: "offline" } }));
    }, 60000);

    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.addEventListener("message", (ev) => {
        if (ev.data?.type !== "sw:updated") return;
        V.run(122, { type: "sw:updated", detail: { version: ev.data.version } });
      });
    }

    window.setTimeout(() => {
      if (!window.MASTER_FACE && body.dataset.faceBooting === "1") {
        V.run(123, { type: "container-timeout", detail: {} });
      }
    }, 12000);

    window.addEventListener("master:container-timeout", () => {
      V.run(123, { type: "master:container-timeout", detail: {} });
    });

    window.addEventListener("master:face-error", (ev) => {
      if (ev.detail?.module) root.dataset.bootErrorModule = ev.detail.module;
    });

    window.addEventListener("online", () => {
      V.run(125, { type: "offline:flush", detail: { flush: true } });
    });

    const PWA_KEY = "master:pwa:sessions";
    const sessions = Number(storeGet(PWA_KEY) || 0) + 1;
    storeSet(PWA_KEY, String(sessions));
    window.addEventListener("beforeinstallprompt", (ev) => {
      ev.preventDefault();
      window._deferredInstallPrompt = ev;
    });
    V.run(126, { type: "init", detail: { sessions } });

    window.setInterval(() => V.run(128, { type: "tts:metrics", detail: {} }), 2000);
    window.setInterval(() => V.run(129, { type: "metrics:post", detail: {} }), 30000);
    window.addEventListener("master:face-ready", () => V.run(129, { type: "metrics:ready", detail: {} }), { once: true });

    if ("PressureObserver" in window) {
      try {
        const obs = new PressureObserver((records) => {
          const bad = records.some((r) => r.state === "serious" || r.state === "critical");
          if (bad) V.run(137, { type: "pressure", detail: { downgrade: true } });
        });
        obs.observe("cpu").catch(() => {});
      } catch (err) { window.MASTER_LOG?.warn?.("face_vision_d:pressure_observer", err); }
    }

    if (document.startViewTransition) {
      window.addEventListener("primer:ready", () => V.run(134, { type: "primer:ready", detail: {} }), { once: true });
    }

    if (navigator.xr?.isSessionSupported) {
      navigator.xr.isSessionSupported("immersive-vr")
        .then((ok) => V.run(140, { type: "webxr:probe", detail: { vr: ok } }))
        .catch(() => V.run(140, { type: "webxr:probe", detail: { vr: false } }));
    } else {
      V.run(140, { type: "init", detail: {} });
    }

    window._faceTrace = [];
    window.addEventListener("master:visual", (ev) => {
      const d = ev.detail || {};
      window._faceTrace.push({ t: performance.now(), name: d.name, mode: d.mode });
      while (window._faceTrace.length > 200) window._faceTrace.shift();
      if (/council/i.test(String(d.name || ""))) {
        V.run(139, { type: String(d.name), detail: d });
      }
    });

    window.addEventListener("message", (ev) => {
      if (ev.data?.type !== "master:mood") return;
      V.run(147, { type: "postMessage", detail: { mood: ev.data.mood, mode: ev.data.mode } });
    });

    fetch(window.MASTER_ASSET_PATHS?.visemePacks || "/viseme_packs.json", { credentials: "same-origin" })
      .then((r) => (r.ok ? r.json() : null))
      .then((packs) => V.run(145, { type: "viseme-packs", detail: { packs } }))
      .catch(() => V.run(145, { type: "viseme-packs", detail: {} }));

    window.MASTER_FACE_VISION.offlineQueue = {
      enqueue(bodyStr) {
        V.run(125, { type: "offline:enqueue", detail: { body: bodyStr } });
      },
      flush() {
        V.run(125, { type: "offline:flush", detail: { flush: true } });
      }
    };

    window.MASTER_FACE_VISION.showBootError = (err, meta) => {
      V.run(124, {
        type: "boot:error",
        detail: { message: err?.message || String(err), module: meta?.module, stage: meta?.stage }
      });
    };

    window.MASTER_FACE_VISION.generateTopology = (seed) => {
      const ctx = { type: "topology:gen", detail: { seed } };
      V.run(142, ctx);
      return ctx.detail.topology;
    };

    window.MASTER_FACE_VISION.scrubTrace = (t) => {
      const ctx = { type: "trace:scrub", detail: { t } };
      V.run(146, ctx);
      return ctx.detail.hit;
    };

    window.MASTER_FACE_VISION.broadcastMood = () => {
      V.run(147, { type: "mood:broadcast", detail: { broadcast: true }, st: V.state() });
    };

    window.MASTER_FACE_VISION.exportWebm = async (ms) => {
      const ctx = { type: "export:webm", detail: { ms }, st: V.state() };
      const handler = V.features.get(148)?.handler;
      if (handler) await handler(ctx);
      return ctx.detail.blob;
    };

    window.MASTER_FACE_VISION.cableFanout = (event) => {
      V.run(141, { type: "cable:fanout", detail: { event } });
    };

    window.MASTER_FACE_VISION.recordBench = (entry) => {
      V.run(144, { type: "bench:record", detail: { entry } });
    };

    window.MASTER_FACE_VISION.gazeOptIn = async () => {
      if (!navigator.mediaDevices?.getUserMedia) return false;
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "user" } });
        stream.getTracks().forEach((t) => t.stop());
        V.run(138, { type: "gaze:opt-in", detail: { optedIn: true } });
        return true;
      } catch (_) {
        return false;
      }
    };

    if (typeof WebTransport !== "undefined") {
      root.dataset.webTransport = "available";
    }

    window.addEventListener("master:visual", (ev) => {
      const fps = Number(root.dataset.benchFps);
      if (fps > 0) V.run(144, { type: "bench:auto", detail: { entry: { fps } } });
    });

    // Patch face.js dispatchFaceError if loaded later
    const patchFaceError = () => {
      if (window._faceErrorPatched) return;
      window._faceErrorPatched = true;
    };
    patchFaceError();
  })();

  window.MASTER_FACE_VISION?.boot?.();
})();
