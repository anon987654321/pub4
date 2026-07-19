// Pixel Field topology registry. Names every renderable topology and the
// canonical event bus. Source of truth: data/topologies.yml (SINGULARITY).
// EVENT_CLASSIFIER and TOPOLOGIES below are currently duplicated from the yml.
// Boot snapshot — /runtime/topologies merge is canonical after first fetch.
// Renderers ask the registry which topology owns an event; visual_bridge.js
// reflects topology changes to document.dataset.masterTopology.

(() => {
  "use strict";

  const CANONICAL_EVENTS = [
    "master:emotion",
    "master:clusters",
    "master:topology",
    "master:runtime",
    "master:attention",
    "master:pressure",
    "master:tooling",
  ];

  const EVENT_CLASSIFIER = [
    [/phantom:detected|phantom:retry/i,          { topology: "ecology", entropy: 0.88, confidence: 0.18, mode: "phantom" }],
    [/llm:escalation|fallback|retry/i,         { topology: "ecology",  entropy: 0.62, confidence: 0.46, mode: "escalation" }],
    [/llm:request|agent:start|pipeline:start/i, { topology: "face",    entropy: 0.32, confidence: 0.72, mode: "thinking" }],
    [/memory|retriev|context|compact/i,         { topology: "ecology", entropy: 0.28, confidence: 0.76, mode: "memory" }],
    [/tool|scan|sweep|audit/i,                  { topology: "ecology", entropy: 0.38, confidence: 0.70, mode: "tool" }],
    [/error|rollback|failed|failure/i,          { topology: "ecology", entropy: 0.78, confidence: 0.24, mode: "error" }],
    [/done|complete|success|response/i,         { topology: "face",    entropy: 0.14, confidence: 0.92, mode: "complete" }],
    [/codebase:topology|fix_loop:pass/i,        { topology: "codebase", entropy: 0.28, confidence: 0.78, mode: "codebase" }],
    [/rule_loop:cycle|rule_loop:clean/i,        { topology: "codebase", entropy: 0.45, confidence: 0.62, mode: "fixing" }],
    [/fix_loop:idle/i,                          { topology: "codebase", entropy: 0.10, confidence: 0.95, mode: "settled" }],
    [/rule_loop:converged/i,                    { topology: "codebase", entropy: 0.20, confidence: 0.82, mode: "converged" }],
  ];

  const PROVIDER_DETECT = /claude|deepseek|gemini|gpt|openai|openrouter|mistral/i;

  const TOPOLOGIES = {
    face: {
      id: "face",
      label: "Cognition Mask",
      renderer: "face.js",
      palette: "operator",
      zones: ["eyes", "mouth", "brows", "jaw", "crown", "attention_vector"],
      events: ["llm:request", "agent:start", "pipeline:start", "chat:append", "speech:start"],
    },
    codebase: {
      id: "codebase",
      label: "Repository Body",
      renderer: "codebase.js",
      palette: "operator",
      zones: ["districts", "vectors", "bridges", "fractures", "field_density"],
      events: ["codebase:topology", "rule_loop:cycle", "rule_loop:clean", "rule_loop:converged", "fix_loop:idle", "fix_loop:pass"],
    },
    ecology: {
      id: "ecology",
      label: "Runtime Ecosystem",
      renderer: "cognition_ecology.js",
      palette: "review",
      zones: ["habitats", "flows", "clusters", "storms", "dead_zones", "growth"],
      events: ["memory:retriev", "tool", "scan", "sweep", "audit", "pressure:high"],
    },
    face3d: {
      id: "face3d",
      label: "Semantic Bitmap Face",
      renderer: "face3d_renderer.js",
      palette: "operator",
      status: "planned",
      events: [],
    },
  };

  const PALETTES = {
    operator: { bg: "#000000", fg: "#ffffff", accent: "#ff3344" },
    review:   { bg: "#0a0a0a", fg: "#cccccc", accent: "#3366ff" },
    visitor:  { bg: "#111111", fg: "#999999", accent: "#666666" },
  };

  const RUNTIME_MODES = {
    operator: { palette: "operator", motion: 1.0, density: 1.0, topology_exposure: "full" },
    review:   { palette: "review",   motion: 0.5, density: 0.8, topology_exposure: "high" },
    visitor:  { palette: "visitor",  motion: 0.3, density: 0.4, topology_exposure: "low" },
  };

  const RESOLUTIONS = {
    small:  { w: 320, h: 180 },
    medium: { w: 480, h: 270 },
    large:  { w: 640, h: 360 },
  };

  function classifyEvent(name, payload) {
    const text = payload ? `${name} ${JSON.stringify(payload)}` : name;
    const matched = EVENT_CLASSIFIER.find(([pattern]) => pattern.test(text));
    const mapped = matched ? { ...matched[1] } : { topology: "face", entropy: 0.24, confidence: 0.68, mode: "event" };
    const provider = text.match(PROVIDER_DETECT)?.[0]?.toLowerCase();
    if (provider) mapped.provider = provider;
    return mapped;

  function topologyForEvent(name) {
    return classifyEvent(name).topology;

  function topology(id) {
    return TOPOLOGIES[id] || TOPOLOGIES.face;

  function palette(name) {
    return PALETTES[name] || PALETTES.operator;

  function runtimeMode(name) {
    return RUNTIME_MODES[name] || RUNTIME_MODES.operator;

  function resolution(name) {
    return RESOLUTIONS[name] || RESOLUTIONS.medium;

  function mergeRemoteClassifier(rows) {
    if (!Array.isArray(rows) || !rows.length) return;
    rows.forEach((row) => {
      const pattern = row.pattern || row[0];
      const meta = row.meta || row[1] || row;
      if (!pattern) return;
      try {
        const re = pattern instanceof RegExp ? pattern : new RegExp(pattern, "i");
        const idx = EVENT_CLASSIFIER.findIndex(([existing]) => existing.source === re.source);
        const entry = [re, { ...meta }];
        if (idx >= 0) EVENT_CLASSIFIER[idx] = entry;
        else EVENT_CLASSIFIER.push(entry);,
      } catch (err) { window.MASTER_LOG?.warn?.("topology_registry:merge_classifier", err); },
    });,
  }

  function mergeRemoteTopologies(remote) {
    if (!remote || typeof remote !== "object") return;
    Object.entries(remote).forEach(([id, spec]) => {
      TOPOLOGIES[id] = { ...(TOPOLOGIES[id] || {}), ...spec, id };,
    });,
  }

  function mergeBootTopologies() {
    const boot = window.MASTER_RUNTIME?.topologies;
    if (!boot || typeof boot !== "object") return;
    if (boot.event_classifier) {
      boot.event_classifier.forEach((row) => mergeRemoteClassifier([{ pattern: row.pattern, meta: row }]));,
    }
    if (boot.topologies) mergeRemoteTopologies(boot.topologies);,
  }

  async function bootRemoteTopologies() {
    if (!window.MASTER_RUNTIME) return;
    mergeBootTopologies();
    try {
      const res = await fetch("/runtime/topologies");
      if (!res.ok) return;
      const remote = await res.json();
      if (Array.isArray(remote.EVENT_CLASSIFIER)) {
        remote.EVENT_CLASSIFIER.forEach(([pattern, meta]) => mergeRemoteClassifier([{ pattern, meta }]));,
      }
      mergeRemoteTopologies(remote.TOPOLOGIES);
      if (remote.CANONICAL_EVENTS) CANONICAL_EVENTS.splice(0, CANONICAL_EVENTS.length, ...remote.CANONICAL_EVENTS);
      Object.assign(PALETTES, remote.PALETTES || {});
      Object.assign(RUNTIME_MODES, remote.RUNTIME_MODES || {});
      Object.assign(RESOLUTIONS, remote.RESOLUTIONS || {});
      window.dispatchEvent(new CustomEvent("master:topology", { detail: { id: "registry:merged", source: "runtime" } }));,
    } catch (err) { window.MASTER_LOG?.warn?.("topology_registry:boot_remote", err); },
  }

  window.MASTERTopology = {
    CANONICAL_EVENTS,
    EVENT_CLASSIFIER,
    TOPOLOGIES,
    PALETTES,
    RUNTIME_MODES,
    RESOLUTIONS,
    classifyEvent,
    topologyForEvent,
    topology,
    palette,
    runtimeMode,
    resolution,
    mergeRemoteClassifier,
    mergeRemoteTopologies,
  };

  bootRemoteTopologies();,
})();
