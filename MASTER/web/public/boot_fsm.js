// MASTER boot finite-state machine: deterministic boot phases + readiness checks.
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
  const checks = {
    faceReady: false,
    voiceReady: false,
    containerReady: false,
  };

  function log(message, detail) {
    window.MASTER_LOG?.info?.("boot:fsm", message, detail);
    if (typeof console !== "undefined" && console.debug) {
      console.debug("[MASTER boot]", message, detail || "");
    }
  }

  function applyDom() {
    const body = document.body;
    if (body) body.dataset.bootState = state;
    document.documentElement.dataset.bootState = state;
  }

  function snapshot(detail = {}) {
    return {
      state,
      checks: { faceReady: checks.faceReady, voiceReady: checks.voiceReady, containerReady: checks.containerReady },
      at: performance.now(),
      detail,
    };
  }

  function emit(prev, detail) {
    const entry = { from: prev, to: state, ...snapshot(detail) };
    window.dispatchEvent(new CustomEvent("master:boot-state", { detail: entry }));
  }

  function maybeReady(detail = {}) {
    if (!checks.faceReady || !checks.voiceReady || !checks.containerReady) return false;
    if (state === STATES.READY || state === STATES.ERROR) return false;
    return transition(STATES.READY, { ...detail, reason: "all_checks" });
  }

  function transition(next, detail = {}) {
    if (next === state) return false;
    const allowed = TRANSITIONS[state] || [];
    if (next !== STATES.ERROR && !allowed.includes(next)) {
      log("illegal transition", { from: state, to: next, detail });
      return false;
    }
    const prev = state;
    state = next;
    history.push({ from: prev, to: next, at: performance.now(), detail });
    if (history.length > 96) history.shift();
    applyDom();
    log(`${prev} → ${next}`, detail);
    emit(prev, detail);
    if (next === STATES.VOICE) maybeReady(detail);
    return true;
  }

  function setCheck(name, value, detail = {}) {
    if (!(name in checks)) return false;
    const next = !!value;
    if (checks[name] === next) {
      if (next) maybeReady({ ...detail, check: name });
      return false;
    }
    checks[name] = next;
    log(`check ${name}=${next}`, detail);
    emit(state, { ...detail, check: name, value: next });
    if (next) maybeReady({ ...detail, check: name });
    return true;
  }

  // face_ready is sent from a frame that painted, so it answers an ERROR the
  // boot watchdog declared on a clock: a slow device that renders at 42s is
  // up, not failed. The walk back uses only legal edges, so startEverything's
  // own FACE from ERROR stays refused and no frame means no recovery.
  function recoverOnPaint(detail) {
    if (state !== STATES.ERROR) return;
    const recovery = { ...detail, reason: "face_painted_after_error" };
    transition(STATES.RECOVERING, recovery);
    transition(STATES.ASSETS, recovery);
    transition(STATES.FACE, recovery);
    if (checks.voiceReady) transition(STATES.VOICE, recovery);
  }

  function signal(kind, detail = {}) {
    switch (kind) {
      case "face_ready":
        recoverOnPaint(detail);
        return setCheck("faceReady", true, detail);
      case "voice_ready":
        return setCheck("voiceReady", true, detail);
      case "container_ready":
        return setCheck("containerReady", true, detail);
      case "container_warmup":
        checks.containerReady = false;
        emit(state, { ...detail, check: "containerReady", value: false });
        return true;
      case "renderer_failed":
        return transition(STATES.ERROR, { ...detail, reason: "renderer_failed" });
      default:
        return false;
    }
  }

  function resetChecks(detail = {}) {
    checks.faceReady = false;
    checks.voiceReady = false;
    checks.containerReady = false;
    emit(state, { ...detail, reason: "checks_reset" });
  }

  window.addEventListener("master:face-ready", () => {
    signal("face_ready", { source: "master:face-ready" });
  });

  window.addEventListener("master:container-ready", () => {
    signal("container_ready", { source: "master:container-ready" });
  });

  window.addEventListener("master:container-timeout", () => {
    signal("container_warmup", { source: "master:container-timeout" });
  });

  if (document.querySelector('meta[name="master-container-ready"]')?.content === "1") {
    signal("container_ready", { source: "meta" });
  }

  const api = Object.freeze({
    STATES,
    TRANSITIONS,
    state: () => state,
    history: () => history.slice(),
    checks: () => ({
      faceReady: checks.faceReady,
      voiceReady: checks.voiceReady,
      containerReady: checks.containerReady,
    }),
    transition,
    signal,
    resetChecks,
    canTransition: (next) => next === STATES.ERROR || (TRANSITIONS[state] || []).includes(next),
  });

  window.MASTER = window.MASTER || {};
  window.MASTER.boot = api;
  window.MASTER_BOOT_FSM = api;

  applyDom();
  log("INIT");
})();
