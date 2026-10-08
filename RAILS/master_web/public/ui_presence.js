// The application's own signals, published into the presence store.
//
// visual_bridge already turns runtime events into presence -- LLM, pipeline,
// council, memory, tools, TTS, pressure -- and chat.js routes photo capture
// through MASTERVisual. What none of that covers is the person: MASTER read its
// own state closely and had no idea whether anyone was looking at it. The face
// held an attending expression at a tab nobody had in front of them, and gave
// no acknowledgement when they came back.
//
// Read-only. This observes and publishes; it does not change what the shell
// does or looks like. Attention goes to publishAttention rather than publish,
// because the seven felt fields are a positional wire format the server splits
// and attention is a property of the person, not of MASTER's state.
(() => {
  "use strict";

  const HIDDEN = 0;
  const BLURRED = 0.4;
  const READING = 0.7;
  const PRESENT = 1;

  let windowFocused = true;
  let atLiveEdge = true;

  function level() {
    if (document.hidden) return HIDDEN;
    if (!windowFocused) return BLURRED;
    return atLiveEdge ? PRESENT : READING;
  }

  function announce(name, detail = {}) {
    const value = level();
    window.MASTERFeltState?.publishAttention?.(value);
    window.dispatchEvent(new CustomEvent(name, { detail: { ...detail, attention: value } }));
  }

  document.addEventListener("visibilitychange", () => {
    announce(document.hidden ? "ui:away" : "ui:return", { source: "visibility" });
  }, { passive: true });

  // A blurred window is not a hidden one: the tab is still on screen, often
  // beside an editor, so it is lower attention rather than none.
  window.addEventListener("blur", () => {
    windowFocused = false;
    announce("ui:away", { source: "blur" });
  }, { passive: true });

  window.addEventListener("focus", () => {
    windowFocused = true;
    announce("ui:return", { source: "focus" });
  }, { passive: true });

  // Scrolled back through the log is reading, which is attention on the
  // conversation rather than on what is being said now. The threshold is a tap
  // target's worth of slack so a resting scroll position does not flap.
  const EDGE_SLACK_PX = 48;

  function watchScrollback() {
    const log = document.getElementById("chat-log");
    if (!log) return;
    log.addEventListener("scroll", () => {
      const edge = log.scrollHeight - log.scrollTop - log.clientHeight <= EDGE_SLACK_PX;
      if (edge === atLiveEdge) return;
      atLiveEdge = edge;
      announce(edge ? "ui:live" : "ui:reading", { source: "scroll" });
    }, { passive: true });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", watchScrollback, { once: true });
  } else {
    watchScrollback();
  }

  window.MASTERUiPresence = Object.freeze({
    level,
    LEVELS: Object.freeze({ HIDDEN, BLURRED, READING, PRESENT }),
  });
})();
