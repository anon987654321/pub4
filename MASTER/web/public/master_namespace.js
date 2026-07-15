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
    Object.defineProperty(root, name, {
      configurable: true,
      enumerable: true,
      get: resolve,
    });
  });

  window.MASTER = root;
})();