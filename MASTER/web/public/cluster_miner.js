"use strict";

// Browser-side cluster miner bridge.
// This does not scan the repository directly. It observes live visual events and
// groups them into reusable cluster signals that other renderers can consume.

(() => {
  const VERTICAL_CLUSTER_BIAS = Object.freeze({
    marketplace: { face_particle_body: 1.18, cognition_ecology: 0.92, repo_ecology: 1.08 },
    dating: { face_particle_body: 1.05, speech_audio_body: 1.12, cognition_ecology: 0.88 },
    tv: { speech_audio_body: 1.15, cognition_ecology: 1.06, codebase_topology: 0.95 },
    default: { face_particle_body: 1.0, cognition_ecology: 1.0, speech_audio_body: 1.0 }
  });

  function verticalHint() {
    return (document.documentElement.dataset.appHint || window.MASTER_RUNTIME?.app_hint || "default").toString().toLowerCase();
  }

  function verticalBiasFor(clusterId) {
    const hint = verticalHint();
    const table = VERTICAL_CLUSTER_BIAS[hint] || VERTICAL_CLUSTER_BIAS.default;
    return table[clusterId] || 1.0;
  }

  const CLUSTERS = Object.freeze({
    face_particle_body: {
      match: /mood|model|verdict|confidence|tool|tts|speech|stt|gesture|face/i,
      layer: "embodiment",
      emotion: { arousal: 0.35, focus: 0.25 }
    },
    cognition_ecology: {
      match: /memory|retriev|context|compact|entropy|provider|visual|ecology/i,
      layer: "background_world",
      emotion: { arousal: 0.22, focus: 0.18 }
    },
    codebase_topology: {
      match: /codebase|rule_loop|fix_loop|violation|clean|converged|topology/i,
      layer: "repository_body",
      emotion: { arousal: 0.32, focus: 0.45 }
    },
    speech_audio_body: {
      match: /speak|speech|tts|voice|audio|viseme|sentence/i,
      layer: "voice",
      emotion: { arousal: 0.30, focus: 0.18, valence: 0.10 }
    },
    repo_ecology: {
      match: /scan|classify|cluster|score|simulate|critique|apply|rollback/i,
      layer: "repository_mining",
      emotion: { arousal: 0.28, focus: 0.38 }
    }
  });

  const state = {
    clusters: new Map(),
    evidence: [],
    lastEmissionAt: 0
  };

  function now() {
    return performance.now();
  }

  function clamp(v, lo = 0, hi = 1) {
    return Math.max(lo, Math.min(hi, Number(v)));
  }

  function ensureCluster(id, spec) {
    if (!state.clusters.has(id)) {
      state.clusters.set(id, {
        id,
        layer: spec.layer,
        heat: 0,
        confidence: 0.5,
        evidence: [],
        lastSeenAt: 0,
        count: 0
      });
    }
    return state.clusters.get(id);
  }

  function classify(detail = {}) {
    const text = `${detail.name || ""} ${detail.mode || ""} ${detail.topology || ""} ${detail.provider || ""} ${JSON.stringify(detail.raw || {})}`;
    const found = [];
    for (const [id, spec] of Object.entries(CLUSTERS)) {
      if (!spec.match.test(text)) continue;
      found.push({ id, spec });
    }
    if (!found.length) found.push({ id: "cognition_ecology", spec: CLUSTERS.cognition_ecology });
    return found;
  }

  function ingest(detail = {}) {
    const t = now();
    const matches = classify(detail);
    const entropy = clamp(detail.entropy ?? 0.24);
    const confidence = clamp(detail.confidence ?? 0.68);
    const evidence = {
      at: t,
      name: detail.name || "event",
      mode: detail.mode || "event",
      topology: detail.topology || "unknown",
      provider: detail.provider || "unknown",
      entropy,
      confidence
    };

    const vBias = verticalBiasFor;
    for (const { id, spec } of matches) {
      const cluster = ensureCluster(id, spec);
      const bias = vBias(id);
      cluster.heat = clamp(cluster.heat + (0.18 + entropy * 0.28) * bias);
      cluster.confidence = clamp((cluster.confidence * 0.75) + (confidence * 0.25));
      cluster.lastSeenAt = t;
      cluster.count += 1;
      cluster.evidence.push(evidence);
      if (cluster.evidence.length > 12) cluster.evidence.shift();
    }

    state.evidence.push(evidence);
    if (state.evidence.length > 80) state.evidence.shift();
    emitClusterState();
  }

  function tick() {
    const t = now();
    for (const cluster of state.clusters.values()) {
      const age = Math.max(0, t - cluster.lastSeenAt);
      const decay = age > 1200 ? 0.985 : 0.995;
      cluster.heat *= decay;
      if (cluster.heat < 0.002) cluster.heat = 0;
    }
    if (t - state.lastEmissionAt > 1000) emitClusterState();
    requestAnimationFrame(tick);
  }

  function emotionFromClusters() {
    let arousal = 0;
    let focus = 0;
    let valence = 0;
    let confidence = 0;
    let heatTotal = 0;

    for (const [id, cluster] of state.clusters) {
      const spec = CLUSTERS[id] || {};
      const heat = cluster.heat;
      const e = spec.emotion || {};
      arousal += (e.arousal || 0) * heat;
      focus += (e.focus || 0) * heat;
      valence += (e.valence || 0) * heat;
      confidence += cluster.confidence * heat;
      heatTotal += heat;
    }

    if (heatTotal <= 0) return { arousal: 0, valence: 0, focus: 0, confidence: 0.88, fatigue: 0 };
    return {
      arousal: clamp(arousal / heatTotal + heatTotal * 0.08),
      valence: clamp(valence / heatTotal, -1, 1),
      focus: clamp(focus / heatTotal + heatTotal * 0.05),
      confidence: clamp(confidence / heatTotal),
      fatigue: clamp(Math.max(0, heatTotal - 2.0) * 0.12)
    };
  }

  function snapshot() {
    return {
      clusters: [...state.clusters.values()].map(cluster => ({
        id: cluster.id,
        layer: cluster.layer,
        heat: Number(cluster.heat.toFixed(3)),
        confidence: Number(cluster.confidence.toFixed(3)),
        count: cluster.count,
        evidence: cluster.evidence.slice(-4)
      })),
      emotion: emotionFromClusters(),
      evidence: state.evidence.slice(-8)
    };
  }

  function emitClusterState() {
    state.lastEmissionAt = now();
    const detail = snapshot();
    window.dispatchEvent(new CustomEvent("master:clusters", { detail }));

    if (window.Face3DPreview?.engine && detail.emotion) {
      window.Face3DPreview.engine.setEmotion(detail.emotion);
    }
  }

  window.addEventListener("master:visual", event => ingest(event.detail || {}));
  window.addEventListener("master:codebase", event => ingest({ ...(event.detail || {}), name: "codebase:topology", topology: "codebase" }));
  window.addEventListener("master:rule_event", event => ingest({ ...(event.detail || {}), name: event.detail?.status ? `rule_loop:${event.detail.status}` : "rule_loop:event", topology: "codebase" }));

  window.MASTERClusterMiner = Object.freeze({
    state,
    classify,
    ingest,
    snapshot,
    emotion: emotionFromClusters
  });

  requestAnimationFrame(tick);
})();
