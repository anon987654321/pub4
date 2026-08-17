(() => {
  "use strict";

  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const canvas = document.getElementById("cognition-ecology") || makeCanvas();
  const ctx = canvas.getContext("2d", { alpha: true });

  const state = {
    width: 1,
    height: 1,
    dpr: Math.min(devicePixelRatio || 1, 2),
    entropy: 0.14,
    confidence: 0.88,
    activity: 0.18,
    weather: "calm",
    topology: "papua-mask",
    provider: "unknown",
    lastEventAt: performance.now(),
    terrainPhase: 0,
    time: 0
  };

  const agents = [
    { name: "planner", angle: 0.0, radius: 0.26, charge: 0.8, hue: "235,210,175" },
    { name: "coder", angle: 0.9, radius: 0.33, charge: 0.5, hue: "220,200,168" },
    { name: "retriever", angle: 1.8, radius: 0.41, charge: 0.7, hue: "210,192,162" },
    { name: "critic", angle: 2.7, radius: 0.36, charge: 0.4, hue: "195,175,148" },
    { name: "memory", angle: 3.6, radius: 0.48, charge: 0.9, hue: "240,220,188" },
    { name: "judge", angle: 4.5, radius: 0.31, charge: 0.55, hue: "205,185,155" },
    { name: "safety", angle: 5.4, radius: 0.44, charge: 0.65, hue: "225,205,172" }
  ];

  // Start of ecology habitats port to ParticleKernel (visual_clusters.yml + topologies.yml).
  // The 7 agent spirits are now backed by semantic cells (kind based on role).
  let agentsPool = null;
  if (window.ParticleKernel) {
    const K = window.ParticleKernel;
    agentsPool = K.createPool(agents.length);
    agents.forEach((a, idx) => {
      K.spawn(agentsPool, 0, 0, {
        kind: idx + 10, // distinct per agent role
        zone: 2,
        confidence: a.charge,
        arousal: a.charge * 0.8,
        attention: 0.7,
        decay: 0.02
      });
    });
  }

  const memories = [];
  const trails = [];
  const weather = [];
  const terrainImpacts = [];
  const MAX_TRAILS = reducedMotion ? 32 : 128;
  const MAX_WEATHER = reducedMotion ? 64 : 240;
  const MAX_MEMORIES = reducedMotion ? 24 : 88;
  const MAX_IMPACTS = reducedMotion ? 12 : 36;

  function makeCanvas() {
    const node = document.createElement("canvas");
    node.id = "cognition-ecology";
    node.setAttribute("aria-hidden", "true");
    document.body.prepend(node);
    return node;
  }

  let internalW = 640, internalH = 360;

  function resize() {
    state.width = innerWidth;
    state.height = innerHeight;

    // Low internal resolution + integer upscale per data/topologies.yml + visual_clusters.yml.
    // The media query alone — see mask.js. `limits.reducedMotionParticles < 100`
    // asked a particle budget a yes/no question and got "yes" every time, so the
    // 640x360 branch below had never run for anyone.
    const isReduced = reducedMotion;
    let res = { w: 640, h: 360 };
    if (isReduced || (state.width * state.height) < 400000) res = { w: 320, h: 180 };

    internalW = res.w;
    internalH = res.h;

    if (window.ParticleKernel) {
      window.ParticleKernel.fitInternalResolution(canvas, res);
      window.ParticleKernel.configureContext(ctx);
    } else {
      canvas.width = res.w;
      canvas.height = res.h;
      canvas.style.imageRendering = "pixelated";
      ctx.imageSmoothingEnabled = false;
    }

    canvas.style.cssText = [
      "position:fixed",
      "inset:0",
      "width:100vw",
      "height:100vh",
      "z-index:2",
      "pointer-events:none",
      "mix-blend-mode:screen",
      "image-rendering:pixelated"
    ].join(";");
    ctx.setTransform(1, 0, 0, 1, 0, 0);
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, Number(value)));
  }

  function center() {
    return [internalW * 0.5, internalH * 0.48];
  }

  function rand(min, max) {
    return min + Math.random() * (max - min);
  }

  function fieldNoise(x, y, t) {
    return Math.sin(x * 0.015 + t) * 0.45 +
      Math.cos(y * 0.019 - t * 0.7) * 0.32 +
      Math.sin((x + y) * 0.009 + t * 1.3) * 0.23;
  }

  function chooseWeather(name) {
    if (/error|rollback|failed|failure/.test(name)) return "storm";
    if (/escalat|fallback|retry/.test(name)) return "serpent";
    if (/memory|retriev|context|compact/.test(name)) return "constellation";
    if (/tool|scan|sweep|audit/.test(name)) return "orbit";
    if (/complete|success|done|idle/.test(name)) return "calm";
    return "thinking";
  }

  let lastBurstAt = 0;

  function ingestVisual(detail = {}) {
    const name = String(detail.name || detail.mode || "event");
    state.lastEventAt = performance.now();
    state.entropy = clamp(detail.entropy ?? state.entropy, 0, 1);
    state.confidence = clamp(detail.confidence ?? state.confidence, 0, 1);
    state.activity = clamp(0.35 + state.entropy + (1 - state.confidence) * 0.5, 0, 1);
    state.topology = detail.topology || state.topology;
    state.provider = detail.provider || state.provider;
    state.weather = chooseWeather(name);

    pulseAgents(name, detail);
    spawnTrail(name, detail);
    spawnTerrainImpact(name, detail);
    if (/memory|retriev|context|compact|chat:append|complete|success/.test(name)) spawnMemory(detail);
    if (/error|rollback|failed|failure|escalat|fallback|retry/.test(name)) spawnWeatherBurst(18, 1.0);
    else spawnWeatherBurst(6, 0.35);
  }

  function pulseAgents(name, detail = {}) {
    for (const agent of agents) {
      if (name.includes(agent.name)) agent.charge = 1;
      else if (/memory|retriev|context/.test(name) && agent.name === "memory") agent.charge = 1;
      else if (/tool|scan|sweep|audit/.test(name) && agent.name === "coder") agent.charge = 0.95;
      else if (/error|rollback|escalat/.test(name) && agent.name === "judge") agent.charge = 1;
      else if (/council:deliberation|council:start|reversibility:low/.test(name)) {
        agent.charge = Math.min(1, agent.charge + 0.32);
        const base = agent._radiusBase ?? agent.radius;
        agent._radiusBase = base;
        const spiritScale = Number(detail?.spirit_radius) || 1.14;
        agent.radius = base * spiritScale;
        setTimeout(() => { agent.radius = base; }, spiritScale > 1.2 ? 1200 : 800);
      }
      else agent.charge = Math.max(agent.charge, 0.55);
    }
    // Mirror charges into the kernel cells (ecology habitats port).
    if (agentsPool) {
      for (let i = 0; i < agentsPool.count; i++) if (agentsPool.alive[i]) {
        const b = i * window.ParticleKernel.FIELDS_PER_CELL;
        const a = agents[i];
        if (a) agentsPool.cells[b + window.ParticleKernel.FIELD.arousal] = a.charge;
      }
    }
  }

  function spawnTrail(name, detail) {
    const [cx, cy] = center();
    const a = rand(0, Math.PI * 2);
    const r = Math.min(state.width, state.height) * rand(0.12, 0.42);
    trails.push({
      x: cx + Math.cos(a) * r,
      y: cy + Math.sin(a) * r,
      vx: Math.cos(a + Math.PI * 0.5) * rand(0.35, 1.4),
      vy: Math.sin(a + Math.PI * 0.5) * rand(0.35, 1.4),
      life: 1,
      width: rand(0.6, 2.2),
      color: colorFor(name, detail),
      name
    });
    while (trails.length > MAX_TRAILS) trails.shift();
  }

  function spawnTerrainImpact(name, detail = {}) {
    const [cx, cy] = center();
    let kind = "rise";
    if (/error|rollback|failed|failure/.test(name)) kind = "fracture";
    else if (/memory|retriev|context|compact/.test(name)) kind = "basin";
    else if (/escalat|fallback|retry|user:interrupt/.test(name)) kind = "rift";
    else if (/input:paste/.test(name)) kind = "basin";
    else if (/complete|success|done/.test(name)) kind = "stabilize";

    terrainImpacts.push({
      x: cx + rand(-0.36, 0.36) * state.width,
      y: cy + rand(-0.30, 0.30) * state.height,
      radius: rand(60, 180),
      life: 1,
      force: kind === "fracture" || kind === "rift" ? 1.0 : 0.55,
      color: colorFor(name, detail),
      kind
    });
    while (terrainImpacts.length > MAX_IMPACTS) terrainImpacts.shift();
  }

  function spawnMemory(detail) {
    const [cx, cy] = center();
    memories.push({
      x: cx + rand(-0.38, 0.38) * state.width,
      y: cy + rand(-0.34, 0.34) * state.height,
      z: rand(0.2, 1),
      life: 1,
      pulse: rand(0, Math.PI * 2),
      label: String(detail.provider || state.provider || "memory")
    });
    while (memories.length > MAX_MEMORIES) memories.shift();
  }

  function spawnWeatherBurst(count, force) {
    const now = performance.now();
    if (now - lastBurstAt < 200) return;
    lastBurstAt = now;
    const storm = state.weather === "storm" || state.weather === "serpent";
    const [cx, cy] = center();
    for (let i = 0; i < count && weather.length < MAX_WEATHER; i++) {
      if (storm) {
        weather.push({
          x: rand(0, internalW),
          y: rand(-0.12, 0.12) * internalH + cy,
          vx: rand(2.2, 5.5) * force,
          vy: rand(-0.15, 0.15),
          life: rand(0.5, 1),
          spin: 0,
          radius: rand(1, 2),
          kind: "streak"
        });
        continue;
      }
      const a = rand(0, Math.PI * 2);
      const speed = rand(0.2, 2.8) * force;
      weather.push({
        x: cx + rand(-0.1, 0.1) * state.width,
        y: cy + rand(-0.1, 0.1) * state.height,
        vx: Math.cos(a) * speed,
        vy: Math.sin(a) * speed,
        life: rand(0.4, 1),
        spin: rand(-0.04, 0.04),
        radius: rand(1, 4 + force * 4),
        kind: "square"
      });
    }
    while (weather.length > MAX_WEATHER) weather.shift();
  }

  function colorFor(name, detail) {
    const conf = detail.confidence ?? state.confidence ?? 0.88;
    const base = Math.round(210 + conf * 35);
    const warm = Math.round(base * 0.90);
    const cool = Math.round(base * 0.78);
    if (/error|rollback|failed|failure/.test(name)) return `${Math.round(base * 0.62)},${warm},${cool}`;
    if (/memory|retriev|context/.test(name)) return `${base},${warm},${Math.round(cool * 1.04)}`;
    if (/tool|scan|sweep|audit/.test(name)) return `${Math.round(base * 0.88)},${warm},${cool}`;
    if (/complete|success|done/.test(name)) return `${base},${base},${Math.round(base * 0.94)}`;
    return `${base},${warm},${cool}`;
  }

  window.addEventListener("resize", resize, { passive: true });

  // Hardened registration: defensive, prefers MASTERTopology classify when present (single source).
  // Addresses prior fragile listener behavior for master:visual events from visual_bridge.
  function onMasterVisual(event) {
    try {
      const detail = event?.detail || {};
      const classified = (window.MASTERTopology && typeof window.MASTERTopology.classifyEvent === "function")
        ? window.MASTERTopology.classifyEvent(detail.name || "event", detail)
        : {};
      ingestVisual({ ...classified, ...detail });
    } catch (_) {
      ingestVisual(event?.detail || {});
    }
  }
  window.addEventListener("master:visual", onMasterVisual);

  window.MASTEREcology = {
    state,
    agents,
    memories,
    trails,
    weather,
    terrainImpacts,
    canvas,
    ctx,
    agentsPool,
    reducedMotion,
    get internalW() { return internalW; },
    get internalH() { return internalH; },
    center,
    fieldNoise,
    colorFor,
    spawnWeatherBurst,
    event: (name, detail = {}) => ingestVisual({ ...detail, name }),
    memory: spawnMemory,
    terrain: spawnTerrainImpact,
    burst: spawnWeatherBurst
  };

  resize();
  for (let i = 0; i < 12; i++) spawnMemory({ provider: "seed" });
})();
