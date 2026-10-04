// Capability and performance policy for the face.
// This is measurement/projection only; visual_governor remains the sole RAF gate.
(() => {
  "use strict";

  const CONTRACT = window.MASTER_FACE_CONTRACT || {};
  const PERFORMANCE = CONTRACT.performance || {};
  const TARGET_FPS = Number(PERFORMANCE.target_fps) || 60;
  const TARGET_FRAME_MS = Number(PERFORMANCE.target_frame_ms) || (1000 / TARGET_FPS);
  const MAIN_THREAD_BUDGET_MS = Number(PERFORMANCE.main_thread_budget_ms) || 8;
  const GPU_BUDGET_MB = Number(PERFORMANCE.gpu_budget_mb) || 128;
  const MEMORY_BUDGET_MB = Number(PERFORMANCE.memory_budget_mb) || 192;
  const HYSTERESIS = Object.freeze({ down: 0.82, up: 1.28 });

  const capabilities = Object.freeze({
    webgl: (() => {
      try {
        const canvas = document.createElement("canvas");
        return Boolean(canvas.getContext("webgl2") || canvas.getContext("webgl"));
      } catch (_) { return false; }
    })(),
    webgpu: Boolean(navigator.gpu),
    offscreenCanvas: typeof OffscreenCanvas === "function",
    audioWorklet: Boolean(window.AudioWorkletNode),
    devicePixelRatio: Number(devicePixelRatio || 1),
    hardwareConcurrency: Number(navigator.hardwareConcurrency || 0),
  });

  const state = {
    lastFrame: 0, frameCount: 0, sampleStart: 0, fps: 0, frameMs: 0,
    quality: "auto", degraded: false, longTasks: 0, resourceBytes: 0,
    renderer: capabilities.webgpu ? "webgl" : "webgl",
    transitions: 0,
    boot: {}, timestamps: {},
  };

  function profile() {
    const root = document.documentElement;
    const requested = root?.dataset?.runtimeProfile || "auto";
    if (requested === "battery" || matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) return "battery";
    if (requested === "studio") return "studio";
    return requested === "tv" ? "tv" : "default";
  }

  function chooseRenderer() {
    // WebGPU is an experimental projection, never a replacement for the
    // WebGL compatibility floor. No WebGPU context is created here.
    state.renderer = capabilities.webgl ? "webgl" : "text";
    if (state.renderer === "webgl" && capabilities.webgpu && location.search.includes("webgpu=1")) {
      state.renderer = "webgpu-capable-webgl-floor";
    }
    document.documentElement.dataset.masterRenderer = state.renderer;
    return state.renderer;
  }

  function mark(name) {
    if (typeof performance?.mark !== "function") return;
    try { performance.mark("master:" + String(name)); state.timestamps[name] = performance.now(); } catch (_) {}
  }

  function recordFrame(now) {
    const t = Number(now);
    if (!Number.isFinite(t)) return;
    if (!state.sampleStart) state.sampleStart = t;
    if (state.lastFrame) state.frameMs = t - state.lastFrame;
    state.lastFrame = t;
    state.frameCount += 1;
    const elapsed = t - state.sampleStart;
    if (elapsed >= 1000) {
      state.fps = state.frameCount * 1000 / elapsed;
      state.frameCount = 0;
      state.sampleStart = t;
      state.degraded = state.fps > 0 && state.fps < 48;
      document.documentElement.dataset.faceFps = state.fps.toFixed(1);
      const next = state.degraded ? "reduced" : "auto";
      if (next !== state.quality && (next === "reduced" || state.fps > TARGET_FPS * HYSTERESIS.up)) {
        state.quality = next;
        state.transitions += 1;
        window.MasterInteraction?.emit?.("render:quality", { quality: next, fps: state.fps });
      }
    }
    window.MasterInteraction?.emit?.("render:frame", {
      fps: state.fps, frameMs: state.frameMs, targetFps: TARGET_FPS
    });
  }

  function bootMarks() {
    mark("first-paint");
    window.addEventListener("master:face-ready", () => {
      mark("face-ready");
      emitReceipt("face-startup");
    }, { once: true });
    window.addEventListener("stt:start", () => {
      mark("first-listening");
      emitReceipt("first-listening");
    }, { once: true });
    window.addEventListener("tts:playback:start", () => {
      mark("first-response");
      emitReceipt("first-response");
    }, { once: true });
  }

  function emitReceipt(kind) {
    const stamp = state.timestamps[kind === "face-startup" ? "face-ready" : kind] || performance.now();
    const receipt = Object.freeze({
      kind, ts: Date.now(), renderer: state.renderer,
      targetFps: TARGET_FPS, targetFrameMs: TARGET_FRAME_MS,
      mainThreadBudgetMs: MAIN_THREAD_BUDGET_MS,
      gpuBudgetMb: GPU_BUDGET_MB, memoryBudgetMb: MEMORY_BUDGET_MB,
      elapsedMs: stamp - (state.timestamps["first-paint"] || stamp),
      capabilities,
    });
    window.MasterInteraction?.emit?.("performance:receipt", receipt);
    window.dispatchEvent(new CustomEvent("master:performance", { detail: receipt }));
  }

  function installObservers() {
    if (typeof PerformanceObserver === "function") {
      try {
        const longtask = new PerformanceObserver((list) => { state.longTasks += list.getEntries().length; });
        longtask.observe({ type: "longtask", buffered: true });
      } catch (_) {}
      try {
        const resources = new PerformanceObserver((list) => {
          list.getEntries().forEach((entry) => {
            state.resourceBytes += Number(entry.transferSize || entry.encodedBodySize || 0);
          });
        });
        resources.observe({ type: "resource", buffered: true });
      } catch (_) {}
    }
  }

  function snapshot() {
    return Object.freeze({
      ...state,
      capabilities,
      targetFps: TARGET_FPS,
      targetFrameMs: TARGET_FRAME_MS,
      mainThreadBudgetMs: MAIN_THREAD_BUDGET_MS,
      gpuBudgetMb: GPU_BUDGET_MB,
      memoryBudgetMb: MEMORY_BUDGET_MB,
      profile: profile()
    });
  }

  chooseRenderer();
  installObservers();
  bootMarks();

  window.MASTER_RENDER_POLICY = Object.freeze({
    TARGET_FPS, TARGET_FRAME_MS, MAIN_THREAD_BUDGET_MS,
    GPU_BUDGET_MB, MEMORY_BUDGET_MB, HYSTERESIS, capabilities,
    profile, chooseRenderer, mark, recordFrame, snapshot
  });
  window.MasterRenderPolicy = window.MASTER_RENDER_POLICY;
})();
