(() => {
  "use strict";

  const CANONICAL = {
    "speech:start": { targets: ["face"], fields: ["id", "source"] },
    "speech:partial": { targets: ["face"], fields: ["text", "transcript"] },
    "speech:end": { targets: ["face"], fields: ["text", "id"] },
    "speech:abort": { targets: ["face"], fields: ["reason", "id"] },
    "speech:attention": { targets: ["face"], fields: ["attention"] },
    "tts:start": { targets: ["face"], fields: ["text", "voice", "style"] },
    "tts:end": { targets: ["face"], fields: ["text", "interrupted"] },
    "tts:interrupt": { targets: ["face"], fields: ["reason", "intent"] },
    "turn:started": { targets: ["face"], fields: ["id", "source"] },
    "turn:committed": { targets: ["face"], fields: ["id", "source", "text"] },
    "turn:discarded": { targets: ["face"], fields: ["id", "reason"] },
    "turn:interrupted": { targets: ["face"], fields: ["id", "reason"] },
    "audio:update": { targets: ["face"], fields: ["rms", "peak", "bass", "mid", "high", "centroid", "onset", "speechActivity"] },
    "render:frame": { targets: ["face"], fields: ["fps", "frameMs", "targetFps"] },
    "render:quality": { targets: ["face"], fields: ["quality", "fps"] },
    "performance:receipt": { targets: ["face"], fields: ["kind", "elapsedMs", "renderer"] },
    "workspace:node:created": { targets: ["face", "ecology"], fields: ["id", "kind", "label"] },
    "workspace:node:updated": { targets: ["face", "ecology"], fields: ["id", "version"] },
    "workspace:node:removed": { targets: ["face", "ecology"], fields: ["id"] },
    "workspace:relation:created": { targets: ["face", "ecology"], fields: ["from", "to", "relation"] },
    "workspace:focus": { targets: ["face"], fields: ["id"] },
    "task:queued": { targets: ["face"], fields: ["id", "kind", "provenance"] },
    "task:active": { targets: ["face"], fields: ["id", "kind"] },
    "task:waiting-human": { targets: ["face"], fields: ["id", "kind"] },
    "task:waiting-network": { targets: ["face"], fields: ["id", "kind"] },
    "task:waiting-model": { targets: ["face"], fields: ["id", "kind"] },
    "task:complete": { targets: ["face"], fields: ["id", "kind"] },
    "task:failed": { targets: ["face"], fields: ["id", "kind"] },
    "task:cancelled": { targets: ["face"], fields: ["id", "kind"] },
    "tool:queued": { targets: ["face"], fields: ["id", "state"] },
    "tool:active": { targets: ["face"], fields: ["id", "state"] },
    "tool:retry": { targets: ["face"], fields: ["id", "state"] },
    "tool:complete": { targets: ["face"], fields: ["id", "state"] },
    "tool:failed": { targets: ["face"], fields: ["id", "state"] },
    "infer:resolved": { targets: ["face", "ecology"], fields: ["command", "confidence", "locale"] },
    "infer:confidence": { targets: ["face"], fields: ["command", "confidence"] },
    "infer:rejected": { targets: ["face"], fields: ["reason", "command"] },
    "route:resolved": { targets: ["face"], fields: ["command", "handler"] },
    "llm:routed": { targets: ["face", "ecology"], fields: ["model", "task_type"] },
    "pressure:updated": { targets: ["ecology", "face"], fields: ["pct", "tokens", "limit"] },
    "ctx:footer": { targets: ["face"], fields: ["pct", "token_est", "model"] },
    "tts:anticipate": { targets: ["face"], fields: ["style", "expression"] },
    "tts:style:active": { targets: ["face"], fields: ["style", "rate", "pitch", "expression"] },
    "tts:playback:start": { targets: ["face"], fields: ["text", "voice", "style", "duration", "backend"] },
    "tts:playback:end": { targets: ["face"], fields: ["text", "interrupted", "backend"] },
    "tts:viseme": { targets: ["face"], fields: ["shape", "amp"] },
    "tts:viseme:plan": { targets: ["face"], fields: ["frames", "visemes", "duration"] },
    "tts:job_cancelled": { targets: ["face"], fields: ["job_id", "reason"] },
    "user:expression": { targets: ["face", "ecology"], fields: ["expression", "blendshapes", "source"] },
    "self_violation": { targets: ["face"], fields: [] },
    "device:battery": { targets: ["face", "ecology"], fields: ["percentage", "status", "health"] },
    "device:network": { targets: ["face", "ecology"], fields: ["connection", "ssid", "ip"] },
    "device:sensors": { targets: ["face"], fields: ["names", "sensors"] },
    "device:accelerometer": { targets: ["face"], fields: [] },
    "device:gyroscope": { targets: ["face"], fields: [] },
    "device:magnetometer": { targets: ["face"], fields: [] },
    "device:light": { targets: ["face"], fields: [] },
    "device:proximity": { targets: ["face"], fields: [] }
  };

  const PROVIDER_PALETTES = {
    claude: { accent: "#9686e8", topology: "face" },
    openai: { accent: "#10a37f", topology: "face" },
    gpt: { accent: "#10a37f", topology: "face" },
    gemini: { accent: "#4285f4", topology: "ecology" },
    deepseek: { accent: "#5b8def", topology: "ecology" },
    mistral: { accent: "#7c6fd6", topology: "ecology" },
    openrouter: { accent: "#8b5cf6", topology: "neural" }
  };

  function normalize(raw) {
    const type = (raw?.type || raw?.event || raw?.name || "runtime:event").toString();
    const payload = raw?.data || raw?.payload || raw;
    const classified = window.MASTERTopology?.classifyEvent?.(type, payload) || {};
    return {
      type,
      ts: Date.now(),
      payload,
      visual: classified,
      schema: CANONICAL[type] || null
    };
  }

  function paletteForProvider(provider) {
    const key = (provider || "").toString().toLowerCase();
    return PROVIDER_PALETTES[key] || window.MASTERTopology?.palette?.("operator") || { accent: "#d8d6e0", topology: "face" };
  }

  function dispatch(normalized) {
    window.dispatchEvent(new CustomEvent("master:bus", { detail: normalized }));
    if (normalized.visual && Object.keys(normalized.visual).length) {
      window.dispatchEvent(new CustomEvent("master:visual", {
        detail: { name: normalized.type, ...normalized.visual, raw: normalized.payload }
      }));
    }
  }

  window.MASTEREvents = { CANONICAL, normalize, dispatch, paletteForProvider, PROVIDER_PALETTES };
})();
