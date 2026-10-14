"use strict";

// The named events ChatService writes on the chat stream split between two
// owners. The handlers below need nothing but window hooks, so either transport
// can use them. mood, model, verdict, confidence, felt, council:speech and
// content_kind drive the face's own State, so they live in handleFaceNamedEvent
// in face.part5.txt, which offers every event there first. sse_contract.test.mjs
// holds the two owners against what ChatService writes.

function parseSseJson(data, fallback) {
  try {
    return JSON.parse(data || "{}");
  } catch (err) {
    window.MASTER_LOG?.warn?.("sse:json", err, data);
    return fallback;
  }
}

function handleThought(data) {
  let line = data;
  if (typeof data === "string" && data.startsWith("{")) {
    const payload = parseSseJson(data, null);
    if (payload && typeof payload === "object") {
      line = payload.text || payload.message || payload.summary || JSON.stringify(payload);
    }
  }
  window._chatOnThought?.(String(line || "").trim());
}

function handleTool(data) {
  const payload = typeof data === "string" && data.startsWith("{") ? parseSseJson(data, {}) : { tool: data };
  const label = [payload.tool, payload.path].filter(Boolean).join(" ");
  window._chatOnDmesg?.(`tool ${label}`.trim());
  window.MASTERVisual?.event?.("tool:start", {
    topology: "terrain",
    entropy: 0.4,
    confidence: 0.7,
    mode: payload.tool || "tool"
  });
}

function handleEnhance(data) {
  const text = String(data || "").replace(/\\n/g, "\n");
  window._chatOnDmesg?.(`enhance: ${text.slice(0, 160)}`);
  window.MASTERVisual?.event?.("enhance:rewrite", {
    topology: "papua-mask",
    entropy: 0.15,
    confidence: 0.88,
    mode: "enhance"
  });
}

function handleDmesg(data) {
  const payload = parseSseJson(data, data);
  window._chatOnDmesg?.(typeof payload === "string" ? payload : String(payload));
}

const NAMED_HANDLERS = {
  thought: handleThought,
  tool: handleTool,
  enhance: handleEnhance,
  dmesg: handleDmesg,
  compaction: (data) => window._chatOnCompaction?.(parseSseJson(data, {})),
  ctx_footer: (data) => window._chatOnCtxFooter?.(parseSseJson(data, {})),
  phantom: (data) => window._chatOnPhantom?.(parseSseJson(data, {})),
  tool_stack: (data) => window._chatOnToolStack?.(parseSseJson(data, {})),
  stage: (data) => window._chatOnStage?.(parseSseJson(data, {})),
  client_action: (data) => window.MASTERChat?.triggerClientAction?.(parseSseJson(data, {})),
};

function dispatchNamed(event, data, extensions) {
  if (!event) return false;
  const extra = extensions || {};
  if (typeof extra[event] === "function") {
    try {
      extra[event](data);
      return true;
    } catch (err) {
      window.MASTER_LOG?.error?.(`sse:${event}`, err);
      return false;
    }
  }
  const handler = NAMED_HANDLERS[event];
  if (!handler) return false;
  try {
    handler(data);
    return true;
  } catch (err) {
    window.MASTER_LOG?.error?.(`sse:${event}`, err);
    return false;
  }
}

window.MASTER_SSE = {
  dispatchNamed,
  parseSseJson,
  NAMED_HANDLERS,
};
