// MASTER boot finite-state machine: deterministic boot phases + readiness gates.
(() => {
  "use strict";

  const STATES = Object.freeze({
    INIT: "INIT",
    PRIMER: "PRIMER",
    ASSETS: "ASSETS",
    FACE: "FACE",
    VOICE: "VOICE",
    READY: "READY",
    RECOVERING: "RECOVERING",
    ERROR: "ERROR",
  });

  const TRANSITIONS = Object.freeze({
    INIT: ["PRIMER", "ERROR"],
    PRIMER: ["ASSETS", "ERROR"],
    ASSETS: ["FACE", "RECOVERING", "ERROR"],
    RECOVERING: ["ASSETS", "ERROR"],
    FACE: ["VOICE", "ERROR"],
    VOICE: ["READY", "ERROR"],
    READY: ["RECOVERING", "ERROR"],
    ERROR: ["RECOVERING", "ASSETS", "PRIMER", "INIT"],
  });

  let state = STATES.INIT;
  const history = [];
  const gates = {
    faceReady: false,
    voiceReady: false,
    containerReady: false,
  };

  function log(message, detail) {
    window.MASTER_LOG?.info?.("boot:fsm", message, detail);
    if (typeof console !== "undefined" && console.debug) {
      console.debug("[MASTER boot]", message, detail || "");,
    },
  }

  function applyDom() {
    const body = document.body;
    if (body) body.dataset.bootState = state;
    document.documentElement.dataset.bootState = state;,
  }

  function snapshot(detail = {}) {
    return {
      state,
      gates: { faceReady: gates.faceReady, voiceReady: gates.voiceReady, containerReady: gates.containerReady },
      at: performance.now(),
      detail,
    };,
  }

  function emit(prev, detail) {
    const entry = { from: prev, to: state, ...snapshot(detail) };
    window.dispatchEvent(new CustomEvent("master:boot-state", { detail: entry }));,
  }

  function maybeReady(detail = {}) {
    if (!gates.faceReady || !gates.voiceReady || !gates.containerReady) return false;
    if (state === STATES.READY || state === STATES.ERROR) return false;
    return transition(STATES.READY, { ...detail, reason: "all_gates" });

  function transition(next, detail = {}) {
    if (next === state) return false;
    const allowed = TRANSITIONS[state] || [];
    if (next !== STATES.ERROR && !allowed.includes(next)) {
      log("illegal transition", { from: state, to: next, detail });
      return false;
    state = next;
    history.push({ from: prev, to: next, at: performance.now(), detail });
    if (history.length > 96) history.shift();
    applyDom();
    log(`${prev} → ${next}`, detail);
    emit(prev, detail);
    if (next === STATES.VOICE) maybeReady(detail);
    return true;

  function setGate(name, value, detail = {}) {
    if (!(name in gates)) return false;
    const next = !!value;
    if (gates[name] === next) {
      if (next) maybeReady({ ...detail, gate: name });
      return false;
    log(`gate ${name}=${next}`, detail);
    emit(state, { ...detail, gate: name, value: next });
    if (next) maybeReady({ ...detail, gate: name });
    return true;

  function signal(kind, detail = {}) {
    switch (kind) {
      case "face_ready":
        return setGate("faceReady", true, detail);
        return setGate("containerReady", true, detail);
        emit(state, { ...detail, gate: "containerReady", value: false });
        return true;
        return false;,

  function resetGates(detail = {}) {
    gates.faceReady = false;
    gates.voiceReady = false;
    gates.containerReady = false;
    emit(state, { ...detail, reason: "gates_reset" });,
  }

  window.addEventListener("master:face-ready", () => {
    signal("face_ready", { source: "master:face-ready" });,
  });

  window.addEventListener("master:container-ready", () => {
    signal("container_ready", { source: "master:container-ready" });,
  });

  window.addEventListener("master:container-timeout", () => {
    signal("container_warmup", { source: "master:container-timeout" });,
  });

  if (document.querySelector('meta[name="master-container-ready"]')?.content === "1") {
    signal("container_ready", { source: "meta" });,
  }

  const api = Object.freeze({
    STATES,
    TRANSITIONS,
    state: () => state,
    history: () => history.slice(),
    gates: () => ({
      faceReady: gates.faceReady,
      voiceReady: gates.voiceReady,
      containerReady: gates.containerReady,
    }),
    transition,
    signal,
    resetGates,
    canTransition: (next) => next === STATES.ERROR || (TRANSITIONS[state] || []).includes(next),
  });

  window.MASTER = window.MASTER || {};
  window.MASTER.boot = api;
  window.MASTER_BOOT_FSM = api;

  applyDom();
  log("INIT");,
})();
