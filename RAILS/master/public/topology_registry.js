// Pixel Field topology registry. Names every renderable topology and the
// canonical event bus. Source of truth: data/topologies.yml (SINGULARITY).
// Runtime data is authoritative; this file owns lookup behavior and fallback
// mechanics, not a second copy of the canonical catalog.
// Boot snapshot — /runtime/topologies merge is canonical after first fetch.
// Renderers ask the registry which topology owns an event; visual_bridge.js
// reflects topology changes to document.dataset.masterTopology.

(() => {
  "use strict";

  const CANONICAL_EVENTS = [];

  const EVENT_CLASSIFIER = [];
  let PROVIDER_DETECT = null;

  const TOPOLOGIES = Object.create(null);
  const FALLBACK_FACE = Object.freeze({
    id: "face",
    renderer: "face_world.js"
  });

  const PALETTES = Object.create(null);
  const RUNTIME_MODES = Object.create(null);
  const RESOLUTIONS = Object.create(null);

  function classifyEvent(name, payload) {
    const text = payload ? `${name} ${JSON.stringify(payload)}` : name;
    const matched = EVENT_CLASSIFIER.find(([pattern]) => pattern.test(text));
    const mapped = matched ? { ...matched[1] } : { topology: "face", entropy: 0.24, confidence: 0.68, mode: "event" };
    if (PROVIDER_DETECT) {
      const provider = text.match(PROVIDER_DETECT)?.[0]?.toLowerCase();
      if (provider) mapped.provider = provider;
    }
    return mapped;
  }

  function topologyForEvent(name) {
    return classifyEvent(name).topology;
  }

  function topology(id) {
    return TOPOLOGIES[id] || TOPOLOGIES.face || FALLBACK_FACE;
  }

  function palette(name) {
    return PALETTES[name] || {};
  }

  function runtimeMode(name) {
    return RUNTIME_MODES[name] || {};
  }

  function resolution(name) {
    return RESOLUTIONS[name] || {};
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
    Object.assign(PALETTES, catalog.palettes || {});
    Object.assign(RUNTIME_MODES, catalog.runtime_modes || {});
    Object.assign(RESOLUTIONS, catalog.resolutions || {});
    if (catalog.canonical_events) {
      CANONICAL_EVENTS.splice(0, CANONICAL_EVENTS.length, ...catalog.canonical_events);
    }
    try {
      PROVIDER_DETECT = catalog.provider_detect
        ? new RegExp(catalog.provider_detect, "i")
        : PROVIDER_DETECT;
    } catch (err) {
      window.MASTER_LOG?.warn?.("topology_registry:provider_detect", err);
    }
    if (!TOPOLOGIES.face) TOPOLOGIES.face = { ...FALLBACK_FACE };
  }

  function mergeBootTopologies() {
    mergeCanonicalCatalog(window.MASTER_RUNTIME?.topology_catalog);
    if (!TOPOLOGIES.face) TOPOLOGIES.face = { ...FALLBACK_FACE };
  }

  // /runtime/topologies renders data/topologies.yml verbatim. Translate its
  // lower_snake_case keys at this boundary; keep the values in the canonical
  // data file so this browser module cannot drift into a second catalog.
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
      mergeCanonicalCatalog({
        event_classifier: remoteKey(remote, "EVENT_CLASSIFIER"),
        topologies: remoteKey(remote, "TOPOLOGIES"),
        canonical_events: remoteKey(remote, "CANONICAL_EVENTS"),
        palettes: remoteKey(remote, "PALETTES"),
        runtime_modes: remoteKey(remote, "RUNTIME_MODES"),
        resolutions: remoteKey(remote, "RESOLUTIONS"),
        provider_detect: remoteKey(remote, "PROVIDER_DETECT"),
      });
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
