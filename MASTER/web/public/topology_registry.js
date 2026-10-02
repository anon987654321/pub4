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
    "master:tooling"
  ];

  const EVENT_CLASSIFIER = [];

  const TOPOLOGIES = Object.create(null);
  const FALLBACK_FACE = Object.freeze({
    id: "face",
    label: "Cognition Mask",
    purpose: "Unified semantic face projection",
    renderer: "face_world.js",
    palette: "operator",
    zones: ["eyes", "mouth", "brows", "jaw", "crown", "attention_vector"]
  });

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

  function classifyEvent(name, payload) {
    const text = payload ? `${name} ${JSON.stringify(payload)}` : name;
    const matched = EVENT_CLASSIFIER.find(([pattern]) => pattern.test(text));
    const mapped = matched ? { ...matched[1] } : { topology: "face", entropy: 0.24, confidence: 0.68, mode: "event" };
    const provider = text.match(PROVIDER_DETECT)?.[0]?.toLowerCase();
    if (provider) mapped.provider = provider;
    return mapped;
  }

  function topologyForEvent(name) {
    return classifyEvent(name).topology;
  }

  function topology(id) {
    return TOPOLOGIES[id] || TOPOLOGIES.face || FALLBACK_FACE;
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
        else EVENT_CLASSIFIER.push(entry);
      } catch (err) { window.MASTER_LOG?.warn?.("topology_registry:merge_classifier", err); }
    });
  }

  function mergeRemoteTopologies(remote) {
    if (!remote || typeof remote !== "object") return;
    const rows = Array.isArray(remote) ? remote : Object.entries(remote).map(([id, spec]) => ({ ...spec, id }));
    rows.forEach((spec) => {
      const id = String(spec?.id || "").trim();
      if (!id) return;
      TOPOLOGIES[id] = { ...(TOPOLOGIES[id] || {}), ...spec, id, renderer: "face_world.js" };
    });
  }

  function mergeCanonicalCatalog(catalog) {
    if (!catalog || typeof catalog !== "object") return;
    mergeRemoteClassifier(catalog.event_classifier || []);
    mergeRemoteTopologies(catalog.topologies || []);
    if (!TOPOLOGIES.face) TOPOLOGIES.face = { ...FALLBACK_FACE };
  }

  function mergeBootTopologies() {
    mergeCanonicalCatalog(window.MASTER_RUNTIME?.topology_catalog);
    if (!TOPOLOGIES.face) TOPOLOGIES.face = { ...FALLBACK_FACE };
  }

  // /runtime/topologies is data/topologies.yml rendered verbatim —
  // RuntimeController#topologies does `Master.load_yaml` and renders it with no
  // transformation — so every key arrives in the YAML's own lower_snake_case.
  // This read them in the JS convention for a constant: remote.TOPOLOGIES,
  // remote.PALETTES, remote.CANONICAL_EVENTS, remote.RUNTIME_MODES,
  // remote.RESOLUTIONS, remote.EVENT_CLASSIFIER. All six were undefined, so
  // `|| {}` swallowed every one and the whole remote merge had never once
  // changed a value since it was written.
  //
  // Fixed at the reader rather than by renaming the YAML: lower_snake_case is
  // the data file's convention and SHOUTING is this file's convention for a
  // frozen table. A reader that has to translate between two conventions is
  // where the translation belongs.
  function remoteKey(remote, name) {
    return remote[name.toLowerCase()] ?? remote[name];
  }

  async function bootRemoteTopologies() {
    if (!window.MASTER_RUNTIME) return;
    mergeBootTopologies();
    try {
      const res = await fetch("/runtime/topologies");
      if (!res.ok) return;
      const remote = await res.json();
      // The rows arrive as objects — {pattern, topology, entropy, confidence,
      // mode} — because the endpoint renders the YAML verbatim. Destructuring
      // them as [pattern, meta] left pattern undefined on every row, so
      // mergeRemoteClassifier dropped all of them at its own guard and the
      // casing fix above reached a merge that still did nothing. It already
      // reads either shape, so the rows go through whole.
      mergeRemoteClassifier(remoteKey(remote, "EVENT_CLASSIFIER"));
      mergeRemoteTopologies(remoteKey(remote, "TOPOLOGIES"));
      const canonical = remoteKey(remote, "CANONICAL_EVENTS");
      if (canonical) CANONICAL_EVENTS.splice(0, CANONICAL_EVENTS.length, ...canonical);
      Object.assign(PALETTES, remoteKey(remote, "PALETTES") || {});
      Object.assign(RUNTIME_MODES, remoteKey(remote, "RUNTIME_MODES") || {});
      Object.assign(RESOLUTIONS, remoteKey(remote, "RESOLUTIONS") || {});
      window.dispatchEvent(new CustomEvent("master:topology", { detail: { id: "registry:merged", source: "runtime" } }));
    } catch (err) { window.MASTER_LOG?.warn?.("topology_registry:boot_remote", err); }
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
    mergeRemoteTopologies
  };

  bootRemoteTopologies();
})();
