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

  const FALLBACK_CLASSIFIER = [
    [/phantom:detected|phantom:retry/i, { topology: "glitch", entropy: 0.88, confidence: 0.18, mode: "phantom" }],
    [/compaction:(start|done)|compact/i, { topology: "terrain", entropy: 0.42, confidence: 0.62, mode: "compact" }],
    [/btw:done|agent:(start|end)/i, { topology: "neural", entropy: 0.36, confidence: 0.74, mode: "side-agent" }],
    [/pipeline:stage|skills:triggered/i, { topology: "papua-mask", entropy: 0.30, confidence: 0.80, mode: "stage" }],
    [/ctx:footer/i, { topology: "neural", entropy: 0.22, confidence: 0.84, mode: "ctx" }],
    [/llm:escalation|fallback|retry/i, { topology: "serpent", entropy: 0.62, confidence: 0.46, mode: "escalation" }],
    [/llm:request|agent:start|pipeline:start|infer:resolved|route:resolved|llm:routed/i, { topology: "papua-mask", entropy: 0.32, confidence: 0.72, mode: "thinking" }],
    [/memory|retriev|context/i, { topology: "neural", entropy: 0.28, confidence: 0.76, mode: "memory" }],
    [/tool|scan|sweep|audit|rtk/i, { topology: "torus", entropy: 0.38, confidence: 0.70, mode: "tool" }],
    [/error|rollback|failed|failure/i, { topology: "serpent", entropy: 0.78, confidence: 0.24, mode: "error" }],
    [/done|complete|success|response/i, { topology: "papua-mask", entropy: 0.14, confidence: 0.92, mode: "complete" }],
    [/codebase:topology|fix_loop:pass/i, { topology: "codebase", entropy: 0.28, confidence: 0.78, mode: "codebase" }],
    [/rule_loop:cycle|rule_loop:clean/i, { topology: "codebase", entropy: 0.45, confidence: 0.62, mode: "fixing" }],
    [/fix_loop:idle/i, { topology: "codebase", entropy: 0.10, confidence: 0.95, mode: "settled" }],
    [/rule_loop:converged/i, { topology: "codebase", entropy: 0.20, confidence: 0.82, mode: "converged" }]
  ];

  function classify(type, payload = {}) {
    const text = `${type} ${JSON.stringify(payload)}`;
    const matched = FALLBACK_CLASSIFIER.find(([pattern]) => pattern.test(text));
    const mapped = matched ? { ...matched[1] } : { topology: "sphere", entropy: 0.24, confidence: 0.68, mode: "event" };

    const provider = text.match(/claude|deepseek|gemini|gpt|openai|openrouter|mistral/i)?.[0]?.toLowerCase();
    if (provider) mapped.provider = provider;

    return mapped;
  }
  // handleRuntimeEvent (live SSE path to watched face/ecology) prefers registry
  // classifyEvent for ONE_SOURCE alignment with data/topologies.yml.
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
    window.MASTER_FACE_EXPRESSION?.pushSignal?.({ ...detail, name });
    const blended = window.MASTER_FACE_EXPRESSION?.blendSignals?.();
    if (blended) {
      detail = { ...detail, entropy: blended.entropy, confidence: blended.confidence, arousal: blended.arousal, valence: blended.valence };
    }
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
    const emotion = {
      arousal: clamp(detail.arousal ?? (0.22 + (1 - state.confidence) * 0.55 + state.entropy * 0.28), 0, 1),
      valence: clamp(detail.valence ?? (state.confidence - state.entropy * 0.35), -1, 1),
      focus: clamp(detail.focus ?? state.confidence, 0, 1),
      confidence: state.confidence,
      fatigue: clamp(detail.fatigue ?? Math.max(0, state.entropy - 0.35) * 0.4, 0, 1),
      mode: visual.mode,
      source: name
    };
    window.dispatchEvent(new CustomEvent("master:emotion", { detail: emotion }));
    if (canonical && canonical !== state.canonicalTopology) {
      state.canonicalTopology = canonical;
      window.dispatchEvent(new CustomEvent("master:topology", { detail: { id: canonical, source: name } }));
      document.documentElement.dataset.topologyFlash = "1";
      setTimeout(() => { delete document.documentElement.dataset.topologyFlash; }, 90);
    }

    if (window.MASTERMask && typeof window.MASTERMask.event === "function") {
      window.MASTERMask.event(name, visual);
    }

    if (window.MASTER_FACE && typeof window.MASTER_FACE.event === "function") {
      window.MASTER_FACE.event(name, visual);
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

  // A viseme plan is played by face_speech_playback.js against the clock of the
  // audio it belongs to. This file used to play a second copy of it on
  // setTimeout, guarded by `if (window.MASTER_FACE?.tts) return` — so it ran
  // only when the face runtime was absent, which is exactly when every listener
  // for tts:viseme is absent too: face_semantics.js and face_vision_c.js are
  // face modules, and face_2d_fallback.js has no mouth. It emitted into an empty
  // room on timers that outlived the condition they were armed under. The plan
  // itself still forwards below, as every other named runtime event does.

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
    if (type === "self_violation") {
      window.dispatchEvent(new CustomEvent("master:self_violation", { detail: event }));
    }
    if (type === "tts:anticipate") {
      window.dispatchEvent(new CustomEvent("tts:anticipate", { detail: event }));
    }
    if (type === "tts:style:active") {
      window.dispatchEvent(new CustomEvent("tts:style:active", { detail: event }));
      window.dispatchEvent(new CustomEvent("master:visual", { detail: { ...event, name: type, raw: event } }));
    }
    if (/^tts:playback:/.test(type)) {
      window.dispatchEvent(new CustomEvent(type, { detail: event }));
    }
    if (type === "tts:viseme:plan") {
      window.dispatchEvent(new CustomEvent("tts:viseme:plan", { detail: event }));
    }
    if (type === "tts:job_cancelled") {
      window.dispatchEvent(new CustomEvent("tts:job_cancelled", { detail: event }));
      window.MASTER_FACE?.ttsSkip?.();
    }
    if (type === "user:expression") {
      window.dispatchEvent(new CustomEvent("user:expression", { detail: event }));
      window.dispatchEvent(new CustomEvent("master:visual", { detail: { ...event, name: type, expression: event.expression, raw: event } }));
    }
    if (/pressure:updated|ctx:footer/i.test(type)) {
      const pct = event.pct ?? event.value ?? 0;
      window.dispatchEvent(new CustomEvent("master:pressure", { detail: { pct, ...event } }));
    }
    if (/council:deliberation|council:start/i.test(type)) {
      startCouncilRotator();
      const spiritRadius = event.spirit_radius ?? event.spiritRadius ?? 1.14;
      window.dispatchEvent(new CustomEvent("master:visual", {
        detail: { name: type, mode: "council", entropy: 0.42, confidence: 0.62, spirit_radius: spiritRadius, raw: event }
      }));
      document.documentElement.dataset.councilBreath = "1";
    }
    if (/phantom:detected|phantom:retry/i.test(type)) {
      window.dispatchEvent(new CustomEvent("master:visual", { detail: { name: type, mode: "phantom", entropy: 0.9, confidence: 0.18, flinch: 1, raw: event } }));
    }
    if (/council:(?:vote|speech|end)|tribunal:rendered/i.test(type)) {
      stopCouncilRotator();
      delete document.documentElement.dataset.councilBreath;
    }
    if (/infer:resolved|infer:confidence|route:resolved|llm:routed/i.test(type)) {
      window.dispatchEvent(new CustomEvent("master:visual", { detail: mapped }));
    }
    if (state.provider && window.MASTEREvents?.paletteForProvider) {
      const pal = window.MASTEREvents.paletteForProvider(state.provider);
      document.documentElement.style.setProperty("--master-accent", pal.accent || "#d8d6e0");
      window.dispatchEvent(new CustomEvent("master:palette", { detail: { provider: state.provider, ...pal } }));
    }
  }

  let eventSource = null;
  let sseErrorCount = 0;
  let cableSocket = null;
  let cableIdent = null;
  const COUNCIL_ROTATOR = ["Architect", "Skeptic", "Pragmatist", "Security", "Mentor"];
  let councilRotatorIdx = 0;
  let councilRotatorTimer = null;

  function startCouncilRotator() {
    if (councilRotatorTimer) return;
    const ui = document.getElementById("ui-status");
    councilRotatorTimer = setInterval(() => {
      if (!ui) return;
      const name = COUNCIL_ROTATOR[councilRotatorIdx % COUNCIL_ROTATOR.length];
      councilRotatorIdx += 1;
      ui.textContent = `council · ${name}`;
    }, 1800);
  }

  function stopCouncilRotator() {
    if (!councilRotatorTimer) return;
    clearInterval(councilRotatorTimer);
    councilRotatorTimer = null;
  }

  function connectCableFallback() {
    if (cableSocket || !window.WebSocket) return;
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    cableSocket = new WebSocket(`${proto}//${location.host}/cable`);
    cableIdent = JSON.stringify({ channel: "MasterChannel" });
    cableSocket.onopen = () => {
      cableSocket.send(JSON.stringify({ command: "subscribe", identifier: cableIdent }));
      emitVisual("events:connected", { topology: "papua-mask", entropy: 0.16, confidence: 0.88, mode: "cable" });
    };
    cableSocket.onmessage = (message) => {
      try {
        const frame = JSON.parse(message.data);
        if (frame.type === "ping") return;
        if (frame.type === "confirm_subscription") return;
        const payload = frame.message;
        if (!payload) return;
        handleRuntimeEvent(payload.event ? { ...payload, type: payload.event } : payload);
      } catch (_error) {
        window.MASTER_LOG?.warn?.("visual_bridge:cable_frame", _error);
      }
    };
    cableSocket.onclose = () => { cableSocket = null; };
    cableSocket.onerror = () => { try { cableSocket.close(); } catch (err) { window.MASTER_LOG?.warn?.("visual_bridge:cable_close", err); } cableSocket = null; };
  }

  function disconnectSse() {
    if (!eventSource) return;
    try { eventSource.close(); } catch (err) { window.MASTER_LOG?.warn?.("visual_bridge:sse_close", err); }
    eventSource = null;
    state.connected = false;
  }

  function connectSse() {
    if (!window.EventSource || eventSource || document.hidden) return;

    eventSource = new EventSource("/events/stream");
    eventSource.onopen = () => {
      state.connected = true;
      sseErrorCount = 0;
      delete document.body.dataset.linkQuiet;
      emitVisual("events:connected", { topology: "papua-mask", entropy: 0.16, confidence: 0.90, mode: "connected" });
    };
    eventSource.onmessage = (message) => {
      try {
        handleRuntimeEvent(JSON.parse(message.data));
      } catch (_error) {
        window.MASTER_LOG?.warn?.("visual_bridge:sse_frame", _error);
        emitVisual("events:raw", { topology: "sphere", entropy: 0.24, confidence: 0.62, raw: message.data });
      }
    };
    eventSource.onerror = () => {
      state.connected = false;
      sseErrorCount += 1;
      state.confidence = Math.max(0.2, state.confidence - 0.1);
      emitVisual("events:disconnected", { topology: "serpent", entropy: 0.52, confidence: state.confidence, mode: "disconnected" });
      document.body.dataset.linkQuiet = "1";
      window._chatOnDmesg?.("link quiet");
      disconnectSse();
      if (sseErrorCount >= 3 && window.MASTER_RUNTIME?.enhancements?.includes?.("actioncable_fallback")) {
        connectCableFallback();
      } else {
        setTimeout(connectSse, Math.min(8000, 500 * sseErrorCount));
      }
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
      let appendQueue = 0;
      const observer = new MutationObserver((mutations) => {
        const added = mutations.reduce((sum, mutation) => sum + mutation.addedNodes.length, 0);
        if (added <= 0) return;
        appendQueue += added;
        if (appendQueue === added) {
          queueMicrotask(() => {
            const n = appendQueue;
            appendQueue = 0;
            if (n > 0) emitVisual("chat:append", { topology: "papua-mask", entropy: 0.18, confidence: 0.88, mode: "response", count: n });
          });
        }
      });
      observer.observe(log, { childList: true, subtree: true });
    }
  }

  function bootEmotionalTimeline() {
    const params = new URLSearchParams(window.location.search);
    if (params.get("timeline") !== "1") return;
    let strip = document.getElementById("emotional-timeline");
    if (!strip) {
      strip = document.createElement("div");
      strip.id = "emotional-timeline";
      strip.className = "emotional-timeline";
      strip.setAttribute("aria-hidden", "true");
      document.body.appendChild(strip);
    }
    const ring = [];
    window.addEventListener("master:visual", (ev) => {
      const d = ev.detail || {};
      ring.push({ mode: (d.mode || "idle").toString().slice(0, 10), entropy: Number(d.entropy ?? 0.2) });
      while (ring.length > 24) ring.shift();
      strip.innerHTML = ring.map((e) => {
        const h = 3 + e.entropy * 10;
        return `<span style="height:${h}px" title="${e.mode}"></span>`;
      }).join("");
    });
  }

  // Honour the deferred-boot contract: nothing heavy (THREE.js, the cluster miner)
  // may load at page load — only after the primer tap. Eager boot here wedged the
  // main thread before the tap could register (dead "tap to start"). _primerFired
  // is the cross-module flag the inline boot sets in go().
  function whenPrimed(run) {
    if (window._primerFired) { run(); return; }
    let done = false;
    const fire = () => { if (done) return; done = true; clearInterval(poll); run(); };
    const primer = document.getElementById("primer");
    if (primer) {
      ["pointerdown", "touchend", "click"].forEach(ev => primer.addEventListener(ev, fire, { once: true, passive: true }));
    }
    addEventListener("keydown", e => { if (e.key === "Enter" || e.key === " ") fire(); }, { once: true });
    const poll = setInterval(() => { if (window._primerFired) fire(); }, 200);
  }

  function bootExperimentalVisuals() {
    const params = new URLSearchParams(window.location.search);
    const clusters = params.get("clusters") === "1";

    if (clusters && !window.MASTERClusterMiner) {
      const script = document.createElement("script");
      script.src = window.MASTER_ASSET_PATHS?.clusterMiner || "/cluster_miner.js";
      script.defer = true;
      script.onload = () => emitVisual("clusters:ready", { topology: "neural", entropy: 0.18, confidence: 0.86, mode: "clusters" });
      script.onerror = () => emitVisual("clusters:error", { topology: "serpent", entropy: 0.62, confidence: 0.36, mode: "error" });
      document.head.appendChild(script);
    }
  }

  window.MASTERVisual = {
    state,
    event: emitVisualNow,
    runtime: handleRuntimeEvent,
    classify
  };

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) disconnectSse();
    else connectSse();
  }, { passive: true });

  observeDomSignals();
  connectSse();
  bootEmotionalTimeline();
  whenPrimed(bootExperimentalVisuals);
  emitVisual("visual:ready", { topology: "papua-mask", entropy: 0.14, confidence: 0.92, mode: "ready" });
})();
