// Pixel Field topology registry. Names every renderable topology and the
// canonical event bus. Source of truth: data/topologies.yml.
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
    "master:tooling"
  ];

  const TOPOLOGIES = {
    face: {
      id: "face",
      label: "Cognition Mask",
      renderer: "face.js",
      palette: "operator",
      zones: ["eyes", "mouth", "brows", "jaw", "crown", "attention_vector"],
      events: ["llm:request", "agent:start", "pipeline:start", "chat:append", "speech:start"]
    },
    codebase: {
      id: "codebase",
      label: "Repository Body",
      renderer: "codebase.js",
      palette: "operator",
      zones: ["districts", "vectors", "bridges", "fractures", "field_density"],
      events: ["codebase:topology", "rule_loop:cycle", "rule_loop:clean", "rule_loop:converged", "fix_loop:idle", "fix_loop:pass"]
    },
    ecology: {
      id: "ecology",
      label: "Runtime Ecosystem",
      renderer: "cognition_ecology.js",
      palette: "review",
      zones: ["habitats", "flows", "clusters", "storms", "dead_zones", "growth"],
      events: ["memory:retriev", "tool", "scan", "sweep", "audit", "pressure:high"]
    },
    face3d: {
      id: "face3d",
      label: "Semantic Bitmap Face",
      renderer: "face3d_renderer.js",
      palette: "operator",
      status: "planned",
      events: []
    }
  };

  const PALETTES = {
    operator: { bg: "#000000", fg: "#ffffff", accent: "#ff3344" },
    review:   { bg: "#0a0a0a", fg: "#cccccc", accent: "#3366ff" },
    visitor:  { bg: "#111111", fg: "#999999", accent: "#666666" }
  };

  const RUNTIME_MODES = {
    operator: { palette: "operator", motion: 1.0, density: 1.0, topology_exposure: "full" },
    review:   { palette: "review",   motion: 0.5, density: 0.8, topology_exposure: "high" },
    visitor:  { palette: "visitor",  motion: 0.3, density: 0.4, topology_exposure: "low" }
  };

  const RESOLUTIONS = {
    small:  { w: 320, h: 180 },
    medium: { w: 480, h: 270 },
    large:  { w: 640, h: 360 }
  };

  function classifyEvent(name) {
    for (const id in TOPOLOGIES) {
      const topology = TOPOLOGIES[id];
      if (topology.events.some(pattern => name.includes(pattern))) return id;
    }
    return "face";
  }

  function topology(id) {
    return TOPOLOGIES[id] || TOPOLOGIES.face;
  }

  function palette(name) {
    return PALETTES[name] || PALETTES.operator;
  }

  function runtimeMode(name) {
    return RUNTIME_MODES[name] || RUNTIME_MODES.operator;
  }

  function resolution(name) {
    return RESOLUTIONS[name] || RESOLUTIONS.medium;
  }

  window.MASTERTopology = {
    CANONICAL_EVENTS,
    TOPOLOGIES,
    PALETTES,
    RUNTIME_MODES,
    RESOLUTIONS,
    classifyEvent,
    topology,
    palette,
    runtimeMode,
    resolution
  };
})();
