// Canonical window.MASTER facade — legacy globals remain as shims during migration.
(() => {
  "use strict";

  const root = window.MASTER || {};

  const namespaces = [
    ["boot", () => root.boot || window.MASTER_BOOT_FSM],
    ["face", () => window.MASTER_FACE],
    ["speech", () => window.MASTERVoice],
    ["speechRuntime", () => window.MASTER_SPEECH_RUNTIME],
    ["speechPlayback", () => window.MASTER_SPEECH_PLAYBACK],
    ["events", () => window.MASTEREvents],
    ["visual", () => window.MASTERVisual],
    ["topology", () => window.MASTERTopology],
    ["ecology", () => window.MASTEREcology],
    ["chat", () => window.MASTERChat],
    ["container", () => window.MASTER_CONTAINER],
    ["sse", () => window.MASTER_SSE],
    ["attention", () => window.MASTER_ATTENTION || root.attention],
    ["felt", () => window.MASTERFeltState],
    ["vision", () => window.MASTER_FACE_VISION],
    ["shortcuts", () => window.MASTERShortcuts],
  ];

  namespaces.forEach(([name, resolve]) => {
    if (Object.prototype.hasOwnProperty.call(root, name)) return;
    let shim;
    Object.defineProperty(root, name, {
      configurable: true,
      enumerable: true,
      // Prefer the resolved canonical global; fall back to a value assigned by a
      // legacy `window.MASTER.<name> = …` shim. Without the setter, those legacy
      // assignments (attention_model.js, face.runtime.js, face_speech_runtime.js)
      // threw "Cannot set property … which has only a getter" in strict mode when
      // they loaded AFTER this facade — which killed the entire face boot
      // (attention_model is the first FACE_MODULE loadFace imports). This was the
      // real black-face root cause.
      get: () => {
        const v = resolve();
        return (v === undefined || v === null) ? shim : v;
      },
      set: (v) => { shim = v; },
    });
  });

  window.MASTER = root;
})();
