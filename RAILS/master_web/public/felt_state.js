// MASTER presence state: the one felt-state reader, and the store behind it.
//
// The felt-state string is not decoration — chat_service.rb splits it into
// mood, mode, entropy, confidence, arousal, valence and hist_entropy, publishes
// it on the bus as felt:sense, and hands it to TurnRouter as felt_sense, so it
// reaches the reply. It has to be the same string wherever it is read.
//
// It was not. This file derived every field by reading back what other modules
// had already written to the DOM — --master-entropy and --master-confidence off
// the root style, masterState and pipelineStage off body.dataset. visual_bridge
// computes all of those in emitVisualNow and dispatches them on master:visual
// and master:emotion *before* reflectToDom writes them out, so scraping the
// reflection made a CSS custom property the transport for the value rather than
// a presentation of it: everything the round-trip through a string-valued
// property dropped was gone by the time it was read back.
//
// Publishers push now. The scrape survives underneath as the fallback for any
// field no publisher has reached yet — which is every field before the first
// event, and mood/mode whenever the face runtime is not up.
(() => {
  "use strict";

  const FELT_FIELD_COUNT = 7;

  // Only fields a publisher has actually set. An absent key falls through to the
  // scrape; a present one wins, so a publisher never has to supply all seven.
  const published = Object.create(null);

  function publishNumber(key, value) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) published[key] = parsed;
  }

  function publishText(key, value) {
    const text = (value ?? "").toString().trim();
    if (text) published[key] = text;
  }

  // Partial by design: visual_bridge knows entropy/confidence/mode, the
  // blendshape bridge knows arousal/valence, the face runtime knows all six.
  //
  // These six and only these six. chat_service.rb splits the felt string by
  // position into mood, mode, entropy, confidence, arousal, valence and
  // hist_entropy, so the string is a wire format and a seventh field would
  // shift everything after it. Anything else the store learns belongs on
  // snapshot(), which callers read by name — see attention below.
  function publish(fields = {}) {
    if (!fields || typeof fields !== "object") return;
    publishText("mood", fields.mood);
    publishText("mode", fields.mode);
    publishNumber("entropy", fields.entropy);
    publishNumber("confidence", fields.confidence);
    publishNumber("arousal", fields.arousal);
    publishNumber("valence", fields.valence);
  }

  // Whether anyone is actually looking, 0..1. Off the wire format on purpose:
  // it is a property of the person rather than of MASTER's own state, and the
  // seven fields are positional.
  let attention = 1;

  function publishAttention(value) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) return;
    attention = Math.max(0, Math.min(1, parsed));
    document.documentElement.dataset.attention = attention.toFixed(2);
  }

  function feltCssNumber(name, fallback) {
    const raw = document.documentElement.style.getPropertyValue(name);
    const parsed = parseFloat(raw);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  function emotionHistoryEntropy(fallback) {
    let history = [];
    try {
      history = JSON.parse(localStorage.getItem("master:emotion_history") || "[]");
    } catch (err) {
      window.MASTER_LOG?.warn?.("felt_state:history", err);
    }
    if (!history.length) return fallback;
    return history.reduce((sum, entry) => sum + Number(entry.entropy ?? 0.2), 0) / history.length;
  }

  // The seven fields as numbers and strings, before they are formatted. Ordered
  // published → scrape → default, per field.
  function snapshot() {
    const st = window.MASTER_FACE?.State || {};
    const histEntropy = emotionHistoryEntropy(st.entropy ?? feltCssNumber("--master-entropy", 0.2));
    const felt = window.MASTER_FACE_BLEND?.currentEmotion?.() || {};
    return {
      mood: published.mood || st.mood || document.body.dataset.masterState || "idle",
      mode: published.mode || st.mode || document.body.dataset.pipelineStage || "idle",
      entropy: published.entropy ?? (Number.isFinite(st.entropy) ? st.entropy : histEntropy),
      confidence: published.confidence
        ?? (Number.isFinite(st.confidence) ? st.confidence : feltCssNumber("--master-confidence", 0.86)),
      arousal: published.arousal ?? felt.arousal ?? (st.pulse ?? 0.4),
      valence: published.valence ?? felt.valence ?? 0,
      histEntropy,
      attention,
    };
  }

  function collectFeltState() {
    const s = snapshot();
    return [
      s.mood.toString(),
      s.mode.toString(),
      s.entropy.toFixed(2),
      s.confidence.toFixed(2),
      s.arousal.toFixed(2),
      s.valence.toFixed(2),
      s.histEntropy.toFixed(2),
    ].join("|");
  }

  function validateFeltState(state) {
    if (typeof state !== "string" || !state.trim()) return false;
    const parts = state.split("|");
    if (parts.length < 4 || parts.length > FELT_FIELD_COUNT) return false;
    if (!parts[0] || !parts[1]) return false;
    return parts.slice(2).every((part) => Number.isFinite(parseFloat(part)));
  }

  function feltStateOrFallback(fallback) {
    const state = collectFeltState();
    if (validateFeltState(state)) return state;
    if (validateFeltState(fallback)) return fallback;
    return null;
  }

  // visual_bridge dispatches both of these with exactly these field names, one
  // rAF-batched frame at a time. Subscribing is what makes the reflection an
  // output rather than the channel.
  window.addEventListener("master:emotion", (ev) => publish(ev.detail || {}), { passive: true });
  window.addEventListener("master:visual", (ev) => publish(ev.detail || {}), { passive: true });

  window.MASTERFeltState = Object.freeze({
    collectFeltState,
    validateFeltState,
    feltStateOrFallback,
    publish,
    publishAttention,
    snapshot,
    FIELD_COUNT: FELT_FIELD_COUNT,
  });
  window.collectFeltState = collectFeltState;
})();
