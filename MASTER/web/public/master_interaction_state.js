// Canonical browser interaction state for MASTER.
// Transport and renderers project this state; they do not own conversation truth.
(() => {
  "use strict";

  const STATES = Object.freeze({
    interaction: ["idle", "waking", "listening", "holding", "yielded", "processing", "speaking", "sleeping", "error"],
    turn: ["draft", "listening", "committed", "interrupted", "discarded", "failed"],
    task: ["queued", "active", "waiting-human", "waiting-network", "waiting-model", "complete", "failed", "cancelled"],
    tool: ["queued", "active", "retry", "complete", "failed"],
    visual: ["idle", "attention", "working", "success", "warning", "error"],
  });

  const LEGACY = Object.freeze({
    "stt:start": ["speech:start", { interaction: "listening" }],
    "stt:partial": ["speech:partial", { interaction: "listening" }],
    "stt:end": ["speech:end", { interaction: "yielded" }],
    "stt:abort": ["speech:abort", { interaction: "idle" }],
    "stt:backchannel": ["speech:attention", { interaction: "listening" }],
    "tts:playback:start": ["tts:start", { interaction: "speaking" }],
    "tts:playback:end": ["tts:end", { interaction: "idle" }],
    "tts:barge_in": ["tts:interrupt", { interaction: "listening" }],
    "tts:job_cancelled": ["tts:interrupt", { interaction: "idle" }],
    "ui:away": ["attention:away", { interaction: "idle" }],
    "ui:return": ["attention:return", { interaction: "idle" }],
    "ui:reading": ["attention:reading", { interaction: "idle" }],
    "ui:live": ["attention:live", { interaction: "idle" }],
  });

  const store = {
    interaction: { state: "idle", version: 0 },
    turn: { state: "draft", id: null, version: 0 },
    audio: {
      rms: 0, peak: 0, bass: 0, mid: 0, high: 0, centroid: 0, onset: 0,
      speechActivity: 0, speaker: "unknown", playback: "closed",
      sentencePosition: 0, sampleRate: 0, channels: 0, analyserWindow: 0,
      latencyMs: null, playbackBufferMs: null, underruns: 0, version: 0
    },
    visual: { state: "idle", topology: "papua-mask", version: 0 },
    task: { state: "idle", active: null, records: [], version: 0 },
    tool: { state: "idle", active: null, records: [], version: 0 },
    memory: { records: [], version: 0 },
  };

  function stableId(prefix = "m") {
    try {
      if (crypto.randomUUID) return crypto.randomUUID();
    } catch (_) {}
    return prefix + "-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8);
  }

  function now() { return Date.now(); }

  function immutable(value) {
    if (typeof structuredClone === "function") {
      try { return structuredClone(value); } catch (_) {}
    }
    return JSON.parse(JSON.stringify(value));
  }

  function valid(bucket, value) {
    return STATES[bucket]?.includes(value) ?? false;
  }

  function record(bucket, state, data = {}, provenance = {}) {
    const ts = now();
    const previous = store[bucket]?.version || 0;
    const next = {
      ...store[bucket],
      state: valid(bucket, state) ? state : store[bucket]?.state,
      version: previous + 1,
      updatedAt: ts
    };
    Object.assign(next, data);
    store[bucket] = next;
    return next;
  }

  function emit(type, payload = {}) {
    const detail = { type: String(type), ts: now(), ...payload };
    window.dispatchEvent(new CustomEvent(detail.type, { detail }));
    window.dispatchEvent(new CustomEvent("master:interaction", { detail }));
    if (window.MASTEREvents?.normalize && window.MASTEREvents?.dispatch) {
      try { window.MASTEREvents.dispatch(window.MASTEREvents.normalize(detail)); } catch (_) {}
    }
    return detail;
  }

  function setInteraction(state, data = {}) {
    const next = record("interaction", state, data);
    emit("interaction:state", { state: next.state, version: next.version, ...data });
    return snapshot();
  }

  function beginTurn(source = "unknown", text = "") {
    const id = stableId("turn");
    store.turn = { id, state: "listening", source, text: String(text), version: 1, createdAt: now(), updatedAt: now() };
    emit("turn:started", { id, source });
    return id;
  }

  function commitTurn(text, source = "voice", extra = {}) {
    const id = store.turn.id || stableId("turn");
    const value = String(text || "").trim();
    store.turn = { ...store.turn, id, state: "committed", source, text: value, version: (store.turn.version || 0) + 1, updatedAt: now(), ...extra };
    emit("turn:committed", { id, source, text: value, ...extra });
    return id;
  }

  function discardTurn(reason = "cancelled") {
    if (!store.turn.id) return false;
    store.turn = { ...store.turn, state: "discarded", version: (store.turn.version || 0) + 1, updatedAt: now(), reason };
    emit("turn:discarded", { id: store.turn.id, reason });
    return true;
  }

  function interruptTurn(reason = "interrupted") {
    if (!store.turn.id) return false;
    store.turn = { ...store.turn, state: "interrupted", version: (store.turn.version || 0) + 1, updatedAt: now(), reason };
    emit("turn:interrupted", { id: store.turn.id, reason });
    return true;
  }

  function taskCreate(kind, data = {}, provenance = {}) {
    const id = stableId("task");
    const task = Object.freeze({
      id, kind: String(kind || "task"), state: "queued", version: 1,
      createdAt: now(), updatedAt: now(),
      provenance: immutable(provenance), data: immutable(data)
    });
    store.task.records = [...store.task.records, task];
    store.task.active = id;
    store.task.state = "queued";
    store.task.version += 1;
    emit("task:queued", task);
    return id;
  }

  function taskUpdate(id, state, data = {}) {
    const index = store.task.records.findIndex((row) => row.id === id);
    if (index < 0 || !valid("task", state)) return null;
    const previous = store.task.records[index];
    const next = Object.freeze({ ...previous, state, version: previous.version + 1, updatedAt: now(), data: { ...previous.data, ...immutable(data) } });
    const records = store.task.records.slice();
    records[index] = next;
    store.task.records = records;
    store.task.state = state;
    store.task.active = state === "complete" || state === "failed" || state === "cancelled" ? null : id;
    store.task.version += 1;
    emit("task:" + state, next);
    return immutable(next);
  }

  function toolUpdate(id, state, data = {}, provenance = {}) {
    if (!valid("tool", state)) return null;
    const current = store.tool.records.find((row) => row.id === id);
    const next = Object.freeze({
      ...(current || { id, createdAt: now(), version: 0 }),
      state, version: (current?.version || 0) + 1, updatedAt: now(),
      data: { ...(current?.data || {}), ...immutable(data) },
      provenance: { ...(current?.provenance || {}), ...immutable(provenance) }
    });
    const records = store.tool.records.filter((row) => row.id !== id);
    store.tool.records = [...records, next];
    store.tool.active = state === "complete" || state === "failed" ? null : id;
    store.tool.state = state;
    store.tool.version += 1;
    emit("tool:" + state, next);
    return immutable(next);
  }

  function remember(type, data, provenance = {}) {
    const memory = Object.freeze({
      id: stableId("memory"), type: String(type || "evidence"),
      version: 1, createdAt: now(), updatedAt: now(),
      provenance: immutable(provenance), data: immutable(data)
    });
    store.memory.records = [...store.memory.records.slice(-199), memory];
    store.memory.version += 1;
    emit("memory:added", memory);
    return memory.id;
  }

  function setAudio(data = {}) {
    const next = { ...store.audio, ...data, version: store.audio.version + 1, updatedAt: now() };
    store.audio = next;
    emit("audio:update", immutable(next));
    return snapshot().audio;
  }

  function setVisual(data = {}) {
    const next = { ...store.visual, ...data, version: store.visual.version + 1, updatedAt: now() };
    store.visual = next;
    emit("visual:update", immutable(next));
    return snapshot().visual;
  }

  function handleLegacy(detail = {}) {
    const type = String(detail.type || detail.name || "");
    const mapping = LEGACY[type];
    if (!mapping) return;
    const [canonical, stateChange] = mapping;
    if (stateChange.interaction) setInteraction(stateChange.interaction, { source: type });
    emit(canonical, detail);
  }

  window.addEventListener("stt:start", (event) => {
    beginTurn("voice");
    handleLegacy({ type: "stt:start", ...event.detail });
  });
  window.addEventListener("stt:partial", (event) => {
    handleLegacy({ type: "stt:partial", ...event.detail });
    emit("speech:partial", event.detail || {});
  });
  window.addEventListener("stt:backchannel", (event) => handleLegacy({ type: "stt:backchannel", ...event.detail }));
  window.addEventListener("tts:playback:start", (event) => handleLegacy({ type: "tts:playback:start", ...event.detail }));
  window.addEventListener("tts:playback:end", (event) => handleLegacy({ type: "tts:playback:end", ...event.detail }));
  window.addEventListener("tts:barge_in", (event) => handleLegacy({ type: "tts:barge_in", ...event.detail }));
  window.addEventListener("tts:job_cancelled", (event) => handleLegacy({ type: "tts:job_cancelled", ...event.detail }));
  ["ui:away", "ui:return", "ui:reading", "ui:live"].forEach((type) => {
    window.addEventListener(type, (event) => handleLegacy({ type, ...event.detail }));
  });
  window.addEventListener("master:visual", (event) => {
    const detail = event.detail || {};
    setVisual({
      state: String(detail.mode || detail.name || store.visual.state),
      topology: String(detail.topology || detail.canonical_topology || store.visual.topology)
    });
  });

  function snapshot() {
    return Object.freeze({
      interaction: immutable(store.interaction),
      turn: immutable(store.turn),
      audio: immutable(store.audio),
      visual: immutable(store.visual),
      task: immutable(store.task),
      tool: immutable(store.tool),
      memory: immutable(store.memory)
    });
  }

  window.MasterInteraction = Object.freeze({
    STATES, snapshot, emit, setInteraction, beginTurn, commitTurn, discardTurn, interruptTurn,
    taskCreate, taskUpdate, toolUpdate, remember, setAudio, setVisual
  });
  window.MASTER_INTERACTION = window.MasterInteraction;
})();
