// Voice + typing projection. Speech recognition remains owned by face.part5;
// this module only coordinates the shared interaction surface and recovery UI.
(() => {
  "use strict";

  let lastVoiceText = "";
  let activeVoiceTurn = null;
  let draftKind = "typed";
  let resumeVoiceAfterTyping = false;

  const input = () => document.getElementById("zin");
  const micState = () => document.getElementById("mic-dot");
  const transcript = () => {
    let node = document.getElementById("voice-transcript");
    if (node) return node;
    node = document.createElement("output");
    node.id = "voice-transcript";
    node.className = "voice-transcript sr-only";
    node.setAttribute("aria-live", "polite");
    node.setAttribute("aria-atomic", "true");
    document.body.appendChild(node);
    return node;
  };

  function setMicState(state, detail = {}) {
    const node = micState();
    if (node) {
      node.dataset.captureState = state;
      const text = node.querySelector("[data-mic-state-text]");
      if (text) text.textContent = state;
      node.setAttribute("aria-label", "microphone " + state);
    }
    window.MasterInteraction?.setInteraction?.(
      state === "listening" ? "listening" : state === "processing" ? "processing" : "idle",
      { source: "voice-surface", ...detail }
    );
  }

  function suspendForTyping() {
    const face = window.MASTER_FACE;
    if (!face?.State?.sttActive && !face?.State?.voiceMode) return;
    resumeVoiceAfterTyping = Boolean(face.State.voiceMode);
    try { face.stopSTT?.(); } catch (_) {}
    draftKind = "typed";
    setMicState("closed", { reason: "typing" });
  }

  function resumeAfterTyping() {
    if (!resumeVoiceAfterTyping) return;
    resumeVoiceAfterTyping = false;
    try { window.MASTER_FACE?.startSTT?.(); } catch (_) {}
  }

  function showTranscript(text, final = false) {
    const value = String(text || "").trim();
    if (!value) return;
    lastVoiceText = value;
    transcript().textContent = value;
    const node = input();
    if (node) {
      node.dataset.voiceDraft = final ? "final" : "partial";
      if (!node.value || draftKind === "voice") node.value = value;
    }
  }

  function recoveryButton(action, label) {
    let wrap = document.getElementById("voice-recovery");
    if (!wrap) {
      wrap = document.createElement("div");
      wrap.id = "voice-recovery";
      wrap.className = "voice-recovery";
      wrap.setAttribute("role", "status");
      const parent = input()?.parentElement || document.body;
      parent.appendChild(wrap);
    }
    let button = wrap.querySelector("[data-action='" + action + "']");
    if (!button) {
      button = document.createElement("button");
      button.type = "button";
      button.dataset.action = action;
      wrap.appendChild(button);
    }
    button.textContent = label;
    button.hidden = false;
    return button;
  }

  function clearRecovery() {
    document.getElementById("voice-recovery")?.remove();
  }

  function install() {
    const node = input();
    if (!node || node.dataset.masterVoiceSurface === "1") return;
    node.dataset.masterVoiceSurface = "1";
    node.setAttribute("enterkeyhint", "send");
    node.addEventListener("focus", suspendForTyping);
    node.addEventListener("input", () => {
      draftKind = "typed";
      clearRecovery();
      window.MasterInteraction?.setInteraction?.("idle", { source: "typing" });
    });
    node.addEventListener("keydown", (event) => {
      if (event.key === "Enter" && event.shiftKey) return;
      if (event.key === "Enter" && !event.shiftKey) {
        window.MasterInteraction?.setInteraction?.("processing", { source: "typed-submit" });
      }
    });
    document.querySelector("form")?.addEventListener("submit", () => {
      clearRecovery();
      resumeAfterTyping();
    }, { capture: true });
    if (navigator.virtualKeyboard) {
      navigator.virtualKeyboard.overlaysContent = true;
    }
  }

  window.addEventListener("stt:start", () => {
    activeVoiceTurn = window.MasterInteraction?.snapshot?.().turn?.id || activeVoiceTurn;
    draftKind = "voice";
    setMicState("listening");
  });
  window.addEventListener("stt:partial", (event) => {
    showTranscript(event.detail?.text || event.detail?.transcript || "", false);
  });
  window.addEventListener("stt:end", (event) => {
    showTranscript(event.detail?.text || event.detail?.transcript || lastVoiceText, true);
    setMicState("processing");
  });
  window.addEventListener("stt:abort", () => {
    setMicState("closed");
    window.MasterInteraction?.discardTurn?.("speech-abort");
  });
  window.addEventListener("turn:committed", (event) => {
    if (event.detail?.source === "voice") showTranscript(event.detail.text, true);
    setMicState("processing");
    activeVoiceTurn = null;
  });
  window.addEventListener("tts:playback:start", () => setMicState("processing"));
  window.addEventListener("tts:playback:end", () => setMicState("closed"));
  window.addEventListener("tts:barge_in", () => setMicState("listening", { source: "barge-in" }));
  window.addEventListener("stt:error", () => {
    setMicState("closed");
    const retry = recoveryButton("retry", "retry voice");
    retry.onclick = () => {
      clearRecovery();
      window.MASTER_FACE?.startSTT?.();
    };
  });

  install();
  window.MASTER_VOICE_SURFACE = Object.freeze({
    suspendForTyping, resumeAfterTyping, showTranscript, clearRecovery, install,
    lastVoiceText: () => lastVoiceText
  });
})();
