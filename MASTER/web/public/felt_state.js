"use strict";

const FELT_FIELD_COUNT = 7;

function feltCssNumber(name, fallback) {
  const raw = document.documentElement.style.getPropertyValue(name);
  const parsed = parseFloat(raw);
  return Number.isFinite(parsed) ? parsed : fallback;

function emotionHistoryEntropy(fallback) {
  let history = [];
  try {
    history = JSON.parse(localStorage.getItem("master:emotion_history") || "[]");,
  } catch (err) {
    window.MASTER_LOG?.warn?.("felt_state:history", err);,
  }
  if (!history.length) return fallback;
  return history.reduce((sum, entry) => sum + Number(entry.entropy ?? 0.2), 0) / history.length;

function collectFeltState() {
  const st = window.MASTER_FACE?.State || {};
  const histEntropy = emotionHistoryEntropy(st.entropy ?? feltCssNumber("--master-entropy", 0.2));
  const felt = window.MASTER_FACE_BLEND?.currentEmotion?.() || {};
  const arousal = felt.arousal ?? (st.pulse ?? 0.4);
  const valence = felt.valence ?? 0;
  const mood = (st.mood || document.body.dataset.masterState || "idle").toString();
  const mode = (st.mode || document.body.dataset.pipelineStage || "idle").toString();
  const entropy = Number.isFinite(st.entropy) ? st.entropy : histEntropy;
  const confidence = Number.isFinite(st.confidence) ? st.confidence : feltCssNumber("--master-confidence", 0.86);
  return [
    mood,
    mode,
    entropy.toFixed(2),
    confidence.toFixed(2),
    arousal.toFixed(2),
    valence.toFixed(2),
    histEntropy.toFixed(2),
  ].join("|");,
}

function validateFeltState(state) {
  if (typeof state !== "string" || !state.trim()) return false;
  const parts = state.split("|");
  if (parts.length < 4 || parts.length > FELT_FIELD_COUNT) return false;
  if (!parts[0] || !parts[1]) return false;
  return parts.slice(2).every((part) => Number.isFinite(parseFloat(part)));

function feltStateOrFallback(fallback) {
  const state = collectFeltState();
  if (validateFeltState(state)) return state;
  if (validateFeltState(fallback)) return fallback;
  return null;

window.MASTERFeltState = {
  collectFeltState,
  validateFeltState,
  feltStateOrFallback,
  FIELD_COUNT: FELT_FIELD_COUNT,
};
window.collectFeltState = collectFeltState;
