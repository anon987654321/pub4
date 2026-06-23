(() => {
  "use strict";

  const status = document.getElementById("status-bar") || document.getElementById("status");
  const input = document.getElementById("zin") || document.getElementById("input");
  const face = document.getElementById("face") || document.getElementById("mask");
  const log = document.getElementById("chat-log");

  const state = {
    connected: false,
    lastEventAt: 0,
    entropy: 0.18,
    confidence: 0.86,
    topology: "papua-mask",
    provider: "unknown",
    active: false
  };

  const EVENT_MAP = [
    [/llm:escalation|fallback|retry/i, { topology: "serpent", entropy: 0.62, confidence: 0.46, mode: "escalation" }],
    [/llm:request|agent:start|pipeline:start/i, { topology: "papua-mask", entropy: 0.32, confidence: 0.72, mode: "thinking" }],
    [/memory|retriev|context|compact/i, { topology: "neural", entropy: 0.28, confidence: 0.76, mode: "memory" }],
    [/tool|scan|sweep|audit/i, { topology: "torus", entropy: 0.38, confidence: 0.70, mode: "tool" }],
    [/error|rollback|failed|failure/i, { topology: "serpent", entropy: 0.78, confidence: 0.24, mode: "error" }],
    [/done|complete|success|response/i, { topology: "papua-mask", entropy: 0.14, confidence: 0.92, mode: "complete" }],
    [/codebase:topology|fix_loop:pass/i, { topology: "codebase", entropy: 0.28, confidence: 0.78, mode: "codebase" }],
    [/rule_loop:cycle|rule_loop:clean/i, { topology: "codebase", entropy: 0.45, confidence: 0.62, mode: "fixing" }],
    [/fix_loop:idle/i, { topology: "codebase", entropy: 0.10, confidence: 0.95, mode: "settled" }],
    [/rule_loop:converged/i, { topology: "codebase", entropy: 0.20, confidence: 0.82, mode: "converged" }]
  ];

  function classify(type, payload = {}) {
    const text = `${type} ${JSON.stringify(payload)}`;
    const matched = EVENT_MAP.find(([pattern]) => pattern.test(text));
    const mapped = matched ? { ...matched[1] } : { topology: "sphere", entropy: 0.24, confidence: 0.68, mode: "event" };

    const provider = text.match(/claude|deepseek|gemini|gpt|openai|openrouter|mistral/i)?.[0]?.toLowerCase();
    if (provider) mapped.provider = provider;

    return mapped;
  }
  // Note: EVENT_MAP local is transitional dupe of data/topologies.yml + registry.
  // handleRuntimeEvent (live SSE path to watched face/ecology) now prefers registry
  // classifyEvent for ONE_SOURCE alignment (canonical ecology/face/codebase names + values).
  // This reduces signal fragmentation so particle reactions (kernel arousal/pressure,
  // tints, terrain, agents) are more coherent and calm to watch from afar.

  let _visualBatch = null;
  let _visualBatchTimer = null;

  function flushVisualBatch() {
    _visualBatchTimer = null;
    if (!_visualBatch || !_visualBatch.length) return;
    const items = _visualBatch.splice(0, _visualBatch.length);
    const last = items[items.length - 1];
    emitVisualNow(last.name, last.detail);
  }

  function emitVisual(name, detail = {}) {
    if (!_visualBatch) _visualBatch = [];
    _visualBatch.push({ name, detail });
    if (!_visualBatchTimer) {
      _visualBatchTimer = requestAnimationFrame(flushVisualBatch);
    }
  }

  function emitVisualNow(name, detail = {}) {
    state.lastEventAt = performance.now();
    state.entropy = clamp(detail.entropy ?? state.entropy, 0, 1);
    state.confidence = clamp(detail.confidence ?? state.confidence, 0, 1);
    state.topology = detail.topology || state.topology;
    state.provider = detail.provider || state.provider;
    state.active = !/complete|idle|done/.test(name);

    const canonical = window.MASTERTopology?.topologyForEvent?.(name);
    const visual = {
      name,
      topology: state.topology,
      canonical_topology: canonical,
      entropy: state.entropy,
      confidence: state.confidence,
      provider: state.provider,
      mode: detail.mode || name,
      raw: detail.raw || null
    };

    window.dispatchEvent(new CustomEvent("master:visual", { detail: visual }));
    if (canonical && canonical !== state.canonicalTopology) {
      state.canonicalTopology = canonical;
      window.dispatchEvent(new CustomEvent("master:topology", { detail: { id: canonical, source: name } }));
      document.documentElement.dataset.topologyFlash = "1";
      setTimeout(() => { delete document.documentElement.dataset.topologyFlash; }, 90);
    }

    if (window.MASTERMask && typeof window.MASTERMask.event === "function") {
      window.MASTERMask.event(name, visual);
    }

    if (window.MASTERFace && typeof window.MASTERFace.event === "function") {
      window.MASTERFace.event(name, visual);
    }

    reflectToDom(visual);
  }

  function reflectToDom(visual) {
    document.documentElement.dataset.masterMode = visual.mode;
    document.documentElement.dataset.masterTopology = visual.canonical_topology || visual.topology;
    document.documentElement.style.setProperty("--master-entropy", String(visual.entropy));
    document.documentElement.style.setProperty("--master-confidence", String(visual.confidence));

    if (face) face.style.filter = "";
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, Number(value)));
  }

  function handleRuntimeEvent(event) {
    const type = event?.type || event?.event || event?.data?.event || "runtime:event";
    const mapped = (window.MASTERTopology && typeof window.MASTERTopology.classifyEvent === "function")
      ? window.MASTERTopology.classifyEvent(type, event)
      : classify(type, event);
    mapped.raw = event;
    emitVisual(type, mapped);
    // Architecture #15: forward codebase topology to particle system.
    if (/codebase:topology/i.test(type) && event.modules) {
      window.dispatchEvent(new CustomEvent("master:codebase", { detail: event }));
    }
    if (/rule_loop:(cycle|clean|converged)/i.test(type)) {
      window.dispatchEvent(new CustomEvent("master:rule_event", { detail: event }));
    }
  }

  function connectSse() {
    if (!window.EventSource) return;

    const source = new EventSource("/events/stream");
    source.onopen = () => {
      state.connected = true;
      emitVisual("events:connected", { topology: "papua-mask", entropy: 0.16, confidence: 0.90, mode: "connected" });
    };
    source.onmessage = (message) => {
      try {
        handleRuntimeEvent(JSON.parse(message.data));
      } catch (_error) {
        emitVisual("events:raw", { topology: "sphere", entropy: 0.24, confidence: 0.62, raw: message.data });
      }
    };
    source.onerror = () => {
      state.connected = false;
      state.confidence = Math.max(0.2, state.confidence - 0.1);
      emitVisual("events:disconnected", { topology: "serpent", entropy: 0.52, confidence: state.confidence, mode: "disconnected" });
      window._chatOnDmesg?.("link quiet");
    };
  }

  function observeDomSignals() {
    if (input) {
      input.addEventListener("focus", () => {
        emitVisual("input:focus", {
          topology: "papua-mask",
          entropy: 0.14,
          confidence: 0.88,
          mode: "attending"
        });
      }, { passive: true });
      input.addEventListener("paste", () => {
        emitVisual("input:paste", {
          topology: "papua-mask",
          entropy: 0.25,
          confidence: 0.82,
          mode: "paste"
        });
      }, { passive: true });
      input.addEventListener("input", () => {
        const length = input.value.length;
        const dense = length > 180;
        if (dense) document.documentElement.dataset.inputDense = "1";
        else delete document.documentElement.dataset.inputDense;
        emitVisual(dense ? "input:long" : "input:change", {
          topology: length > 120 ? "neural" : "papua-mask",
          entropy: Math.min(0.55, length / 360),
          confidence: length ? 0.66 : 0.86,
          mode: dense ? "dense" : "typing"
        });
      }, { passive: true });
    }

    if (status) {
      const observer = new MutationObserver(() => {
        const text = status.textContent || "";
        if (!text.trim()) return;
        const mapped = classify(text, { status: text });
        emitVisual(`status:${mapped.mode}`, mapped);
      });
      observer.observe(status, { childList: true, characterData: true, subtree: true });
    }

    if (log) {
      const observer = new MutationObserver((mutations) => {
        const added = mutations.reduce((sum, mutation) => sum + mutation.addedNodes.length, 0);
        if (added > 0) emitVisual("chat:append", { topology: "papua-mask", entropy: 0.18, confidence: 0.88, mode: "response" });
      });
      observer.observe(log, { childList: true, subtree: true });
    }
  }

  function bootExperimentalVisuals() {
    const params = new URLSearchParams(window.location.search);
    const face3d = params.get("face3d") === "1";
    const clusters = face3d || params.get("clusters") === "1";

    if (clusters && !window.MASTERClusterMiner) {
      const script = document.createElement("script");
      script.src = "/cluster_miner.js";
      script.defer = true;
      script.onload = () => emitVisual("clusters:ready", { topology: "neural", entropy: 0.18, confidence: 0.86, mode: "clusters" });
      script.onerror = () => emitVisual("clusters:error", { topology: "serpent", entropy: 0.62, confidence: 0.36, mode: "error" });
      document.head.appendChild(script);
    }

    if (face3d) {
      import("/face3d_preview.js")
        .then(() => emitVisual("face3d:ready", { topology: "papua-mask", entropy: 0.16, confidence: 0.88, mode: "face3d" }))
        .catch(error => emitVisual("face3d:error", { topology: "serpent", entropy: 0.70, confidence: 0.30, mode: "error", raw: String(error?.message || error) }));
    }
  }

  window.MASTERVisual = {
    state,
    event: emitVisualNow,
    runtime: handleRuntimeEvent,
    classify
  };

  observeDomSignals();
  connectSse();
  bootExperimentalVisuals();
  emitVisual("visual:ready", { topology: "papua-mask", entropy: 0.14, confidence: 0.92, mode: "ready" });
})();
