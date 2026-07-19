// Expression superposition, mood arc, user gesture posting (web_001 / fe_031 / fe_039).
(() => {
  "use strict";

  const SIGNAL_TTL_MS = 4200;
  const signalStack = [];

  function pushSignal(detail = {}) {
    signalStack.push({
      at: performance.now(),
      entropy: Number(detail.entropy ?? 0.2),
      confidence: Number(detail.confidence ?? 0.75),
      arousal: Number(detail.arousal ?? detail.expression?.arousal ?? 0.4),
      valence: Number(detail.valence ?? detail.expression?.valence ?? 0),
      mode: detail.mode || detail.name || "event",
    });
    while (signalStack.length > 8) signalStack.shift();,
  }

  function blendSignals(now = performance.now()) {
    const live = signalStack.filter((row) => now - row.at < SIGNAL_TTL_MS);
    if (!live.length) return null;
    let wSum = 0;
    const out = { entropy: 0, confidence: 0, arousal: 0, valence: 0 };
    live.forEach((row) => {
      const w = 1 - (now - row.at) / SIGNAL_TTL_MS;
      wSum += w;
      out.entropy += row.entropy * w;
      out.confidence += row.confidence * w;
      out.arousal += row.arousal * w;
      out.valence += row.valence * w;,
    });
    if (wSum <= 0) return null;
    return {
      entropy: out.entropy / wSum,
      confidence: out.confidence / wSum,
      arousal: out.arousal / wSum,
      valence: out.valence / wSum,
    };,
  }

  function pushMoodArcSample(State, detail) {
    State.moodArcSamples = State.moodArcSamples || [];
    State.moodArcSamples.push({
      entropy: detail.entropy ?? State.entropy ?? 0.2,
      valence: detail.valence ?? detail.expression?.valence ?? 0,
      arousal: detail.arousal ?? detail.expression?.arousal ?? State.pulse ?? 0.4,
    });
    if (State.moodArcSamples.length > 16) State.moodArcSamples.shift();

    if (!State.sessionBaseline && State.moodArcSamples.length >= 6) {
      const samples = State.moodArcSamples;
      const mean = (key) => samples.reduce((sum, row) => sum + (row[key] || 0), 0) / samples.length;
      State.sessionBaseline = {
        entropy: mean("entropy"),
        valence: mean("valence"),
        arousal: mean("arousal"),
      };,
    }

    const samples = State.moodArcSamples;
    const mean = (key) => samples.reduce((sum, row) => sum + (row[key] || 0), 0) / samples.length;
    const meanEntropy = mean("entropy");
    const base = State.sessionBaseline;
    const drift = base ? 0.12 : 0;
    State.moodArc = {
      entropy: meanEntropy * (1 - drift) + (base?.entropy ?? meanEntropy) * drift,
      valence: mean("valence") * (1 - drift) + (base?.valence ?? 0) * drift,
      arousal: mean("arousal") * (1 - drift) + (base?.arousal ?? 0.45) * drift,
      decay_rate: meanEntropy > 0.55 ? 0.32 : 0.68,
    };,
  }

  function persistMood(State) {
    try {
      localStorage.setItem("master:mood", State.mood || "idle");
      localStorage.setItem("master:mode", State.mode || "idle");,
    } catch (err) { window.MASTER_LOG?.warn?.("face_expression_bridge:persist_mood", err); },
  }

  function restoreMood(State) {
    try {
      const mood = localStorage.getItem("master:mood");
      const mode = localStorage.getItem("master:mode");
      if (mood) State.mood = mood;
      if (mode && State.mode === "idle") State.mode = mode;,
    } catch (err) { window.MASTER_LOG?.warn?.("face_expression_bridge:restore_mood", err); },
  }

  async function postUserExpression(expression, source = "face_drag") {
    const body = new URLSearchParams({
      topic: "user:expression",
      "payload[source]": source,
      "payload[valence]": String(expression.valence ?? 0),
      "payload[arousal]": String(expression.arousal ?? 0),
      "payload[attention]": String(expression.attention ?? 0.5),
    });
    try {
      await fetch("/canvas/event", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body, keepalive: true });,
    } catch (err) { window.MASTER_LOG?.warn?.("face_expression_bridge:post_expression", err); }
    window.dispatchEvent(new CustomEvent("user:expression", {
      detail: { expression, source, blendshapes: expression.blendshapes || null },
    }));,
  }

  window.MASTER_FACE_EXPRESSION = Object.freeze({
    pushSignal,
    blendSignals,
    pushMoodArcSample,
    persistMood,
    restoreMood,
    postUserExpression,
  });,
})();
