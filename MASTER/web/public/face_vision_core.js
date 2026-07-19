// MASTER particle face 2026 — vision feature registry (features 1–150).
(() => {
  "use strict";

  const MAX_FEATURES = 150;
  const features = new Map();
  const ROUTES = [
    [/pipeline:stage|pipeline:start|skills:|master:face-stage/i, [1]],
    [/council:/i, [2, 18]],
    [/pressure:|master:pressure|ctx:footer/i, [3]],
    [/valence|mood|expression/i, [4], (d) => d.valence != null],
    [/infer:confidence|confidence/i, [5], (d) => d.confidence != null],
    [/input:focus|attention|focus|attending/i, [6]],
    [/arousal|pulse|speaking/i, [7], (d) => d.arousal != null],
    [null, [8], (d) => d.ts != null || d.raw?.ts != null],
    [/zone|faceZone|mask/i, [9]],
    [/lint/i, [10]], [/scan|depth|sweep/i, [11]],
    [/error|fail|veto|phantom|container-timeout/i, [12]],
    [/felt|emotion_history/i, [13]], [/topology|canonical_topology|mask:/i, [14]],
    [/provider|model|llm:routed/i, [15]], [/token|stream|chunk|chat:append/i, [16]],
    [/tool:/i, [17]], [/memo|compact|freeze/i, [19]], [/prune|cull/i, [20]],
    [/tts:viseme/i, [21]], [/tts:anticipate|tts:prefetch/i, [22]],
    [/tts:playback:end/i, [23]], [/tts:playback:start/i, [24]],
    [/pitch|tts:style/i, [25]], [/word|boundary|viseme:plan/i, [26]],
    [/tts:job|queue/i, [27]], [/speechSynthesis|browser.*tts/i, [28]],
    [/synth|tts:loading/i, [29]], [/partial|tts:chunk/i, [30]],
    [/locale|lang|multilingual/i, [31]], [/whisper|ethereal|intimate/i, [32]],
    [/council:multi|council:speech|council:deliberation/i, [33]],
    [/stt:/i, [34]], [/tts:error|tts:job_cancelled/i, [35]],
    [/face3d|visual:ready|compositor/i, [36]],
    [/face-ready|boot|primer/i, [37, 40]],
    [/blend|user:expression|face:mouth/i, [38]], [/phosphor|trail/i, [39]]
  ];
  const TTS_EVENTS = [
    "tts:viseme", "tts:playback:start", "tts:playback:end", "tts:anticipate", "tts:style:active",
    "master:tts:viseme", "master:tts:playback:start", "master:tts:playback:end"
  ];
  let primerReadyAt = 0;
  let faceBootMs = 0;
  let particleWorkerAlive = false;
  let booted = false;
  let patched = false;

  function pool() { return window.mouthPool || window.MASTER_FACE?.mouthPool || null; }
  function state() { return window.MASTER_FACE?.State || window.State || {}; }
  function K() { return window.ParticleKernel || null; }

  function spawn(zone, props = {}) {
    const kernel = K();
    const p = pool();
    if (!kernel || !p || p.count >= p.capacity) return -1;
    return kernel.spawn(p, (Math.random() - 0.5) * 0.04, (Math.random() - 0.5) * 0.03, { zone: zone || 0, ...props });
  }

  function css(name, value) {
    if (name) document.documentElement.style.setProperty(name, String(value));
  }

  function register(id, summary, handler) {
    const fid = Number(id);
    if (!Number.isFinite(fid) || fid < 1 || fid > MAX_FEATURES) return false;
    features.set(fid, { id: fid, summary: String(summary || ""), handler: typeof handler === "function" ? handler : null });
    return true;
  }

  function run(id, ctx = {}) {
    const entry = features.get(Number(id));
    if (!entry?.handler) return false;
    try {
      entry.handler({ ...ctx, st: ctx.st || state(), pool: ctx.pool || pool() });
      return true;
    } catch (err) {
      window.MASTER_LOG?.warn?.("face_vision:run", err);
      return false;
    }
  }

  function routeEvent(type, detail = {}) {
    const name = String(type || detail.name || detail.mode || "");
    const ctx = { type: name, detail, st: state(), pool: pool() };
    const routes = [];
    ROUTES.forEach(([re, ids, cond]) => {
      if (re && !re.test(name)) return;
      if (cond && !cond(detail)) return;
      ids.forEach((id) => { if (id >= 1 && id <= MAX_FEATURES) routes.push(id); });
    });
    const seen = new Set();
    routes.forEach((fid) => { if (!seen.has(fid)) { seen.add(fid); run(fid, ctx); } });
    return routes;
  }

  function event(type, detail = {}) { return routeEvent(type, detail); }

  function patchMasterVisual() {
    if (patched || !window.MASTERVisual?.event) return false;
    const orig = window.MASTERVisual.event;
    window.MASTERVisual.event = function patchedVisualEvent(name, detail = {}) {
      routeEvent(name, detail);
      return orig.call(window.MASTERVisual, name, detail);
    };
    patched = true;
    return true;
  }

  function probeParticleWorker() {
    if (!window.Worker || !window.MASTER_RUNTIME?.enhancements?.includes?.("particle_worker")) return;
    try {
      const url = window.MASTER_ASSET_PATHS?.particleWorker
        || window.MASTER_ASSET_PATHS?.faceModules?.["particle_worker.js"] || "/particle_worker.js";
      const worker = new Worker(url);
      const timer = window.setTimeout(() => worker.terminate(), 220);
      worker.onmessage = () => {
        particleWorkerAlive = true;
        document.documentElement.dataset.particleWorker = "alive";
        window.clearTimeout(timer);
        worker.terminate();
      };
      worker.onerror = () => { particleWorkerAlive = false; delete document.documentElement.dataset.particleWorker; };
      worker.postMessage({
        op: "step", id: 0, dt: 0.016, ctx: {}, compact: false,
        pool: { cells: new Float32Array(12).buffer, decay: new Float32Array(1).buffer, alive: new Uint8Array(1).buffer, capacity: 1, count: 0 }
      });
    } catch (err) {
      window.MASTER_LOG?.warn?.("face_vision:worker_ping", err);
      particleWorkerAlive = false;
    }
  }

  function onVisual(ev) {
    patchMasterVisual();
    const d = ev.detail || {};
    routeEvent(String(d.name || d.mode || "master:visual"), d);
  }

  function onTts(ev) { routeEvent(ev.type, ev.detail || {}); }

  function boot() {
    if (booted) return;
    booted = true;
    patchMasterVisual();
    window.addEventListener("master:visual", onVisual);
    TTS_EVENTS.forEach((name) => window.addEventListener(name, onTts));
    window.addEventListener("primer:ready", () => {
      primerReadyAt = performance.now();
      probeParticleWorker();
      run(40, { type: "primer:ready", detail: {} });
    }, { once: true });
    window.addEventListener("master:face-ready", () => {
      if (primerReadyAt > 0) {
        faceBootMs = Math.round(performance.now() - primerReadyAt);
        document.documentElement.dataset.faceBootMs = String(faceBootMs);
        css("--face-boot-ms", faceBootMs);
      }
      run(37, { type: "master:face-ready", detail: { faceBootMs } });
    }, { once: true });
    window.addEventListener("master:face-stage", (ev) => {
      const stage = ev.detail?.stage || "";
      document.documentElement.dataset.faceStage = String(stage).slice(0, 32);
      routeEvent("pipeline:stage", { mode: stage, stage });
    });
    window.addEventListener("master:container-timeout", (ev) => {
      document.documentElement.dataset.containerTimeout = ev.detail?.reason || "1";
      run(12, { type: "master:container-timeout", detail: ev.detail || {} });
    });
    document.addEventListener("visibilitychange", () => {
      document.documentElement.dataset.faceHidden = document.hidden ? "1" : "";
      if (document.hidden) run(19, { type: "visibility:hidden", detail: {} });
    });
    if (window._primerFired && !primerReadyAt) primerReadyAt = performance.now();
    window.setTimeout(patchMasterVisual, 0);
  }

  const impl = {
    get faceBootMs() { return faceBootMs; },
    get particleWorkerAlive() { return particleWorkerAlive; },
    get primerReadyAt() { return primerReadyAt; }
  };

  window.MASTER_FACE_VISION = {
    register, run, routeEvent, features,
    get featureCount() { return features.size; },
    event, boot, impl, pool, state, K, spawn, css
  };
  boot();
})();
