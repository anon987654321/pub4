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
    { name: "planner", angle: 0.0, radius: 0.26, charge: 0.8, hue: "230,180,110" },
    { name: "coder", angle: 0.9, radius: 0.33, charge: 0.5, hue: "120,210,170" },
    { name: "retriever", angle: 1.8, radius: 0.41, charge: 0.7, hue: "120,180,230" },
    { name: "critic", angle: 2.7, radius: 0.36, charge: 0.4, hue: "230,110,90" },
    { name: "memory", angle: 3.6, radius: 0.48, charge: 0.9, hue: "180,230,180" },
    { name: "judge", angle: 4.5, radius: 0.31, charge: 0.55, hue: "220,180,240" },
    { name: "safety", angle: 5.4, radius: 0.44, charge: 0.65, hue: "245,220,160" }
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
  const MAX_TRAILS = reducedMotion ? 24 : 96;
  const MAX_WEATHER = reducedMotion ? 48 : 180;
  const MAX_MEMORIES = reducedMotion ? 18 : 64;
  const MAX_IMPACTS = reducedMotion ? 8 : 28;

  function makeCanvas() {
    const node = document.createElement("canvas");
    node.id = "cognition-ecology";
    node.setAttribute("aria-hidden", "true");
    document.body.prepend(node);
    return node;
  }

  let internalW = 480, internalH = 270;

  function resize() {
    state.width = innerWidth;
    state.height = innerHeight;

    // Low internal resolution + integer upscale per data/topologies.yml + visual_clusters.yml.
    const limits = window.MASTER_VISUAL_LIMITS || {};
    const isReduced = reducedMotion || (limits.reducedMotionParticles && limits.reducedMotionParticles < 100);
    let res = { w: 480, h: 270 };
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
      "z-index:1",
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

  function ingestVisual(detail = {}) {
    const name = String(detail.name || detail.mode || "event");
    state.lastEventAt = performance.now();
    state.entropy = clamp(detail.entropy ?? state.entropy, 0, 1);
    state.confidence = clamp(detail.confidence ?? state.confidence, 0, 1);
    state.activity = clamp(0.35 + state.entropy + (1 - state.confidence) * 0.5, 0, 1);
    state.topology = detail.topology || state.topology;
    state.provider = detail.provider || state.provider;
    state.weather = chooseWeather(name);

    pulseAgents(name);
    spawnTrail(name, detail);
    spawnTerrainImpact(name, detail);
    if (/memory|retriev|context|compact|chat:append|complete|success/.test(name)) spawnMemory(detail);
    if (/error|rollback|failed|failure|escalat|fallback|retry/.test(name)) spawnWeatherBurst(18, 1.0);
    else spawnWeatherBurst(6, 0.35);
  }

  function pulseAgents(name) {
    for (const agent of agents) {
      if (name.includes(agent.name)) agent.charge = 1;
      else if (/memory|retriev|context/.test(name) && agent.name === "memory") agent.charge = 1;
      else if (/tool|scan|sweep|audit/.test(name) && agent.name === "coder") agent.charge = 0.95;
      else if (/error|rollback|escalat/.test(name) && agent.name === "judge") agent.charge = 1;
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
    else if (/escalat|fallback|retry/.test(name)) kind = "rift";
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
    const [cx, cy] = center();
    for (let i = 0; i < count && weather.length < MAX_WEATHER; i++) {
      const a = rand(0, Math.PI * 2);
      const speed = rand(0.2, 2.8) * force;
      weather.push({
        x: cx + rand(-0.1, 0.1) * state.width,
        y: cy + rand(-0.1, 0.1) * state.height,
        vx: Math.cos(a) * speed,
        vy: Math.sin(a) * speed,
        life: rand(0.4, 1),
        spin: rand(-0.04, 0.04),
        radius: rand(1, 4 + force * 4)
      });
    }
    while (weather.length > MAX_WEATHER) weather.shift();
  }

  function colorFor(name, detail) {
    const provider = String(detail.provider || state.provider || "").toLowerCase();
    if (provider.includes("claude")) return "230,120,80";
    if (provider.includes("deepseek")) return "100,170,230";
    if (provider.includes("gemini")) return "180,130,240";
    if (provider.includes("gpt") || provider.includes("openai")) return "120,220,170";
    if (/error|rollback/.test(name)) return "235,70,45";
    if (/memory|retriev/.test(name)) return "135,230,190";
    return "230,180,110";
  }

  function terrainHeight(x, y, t) {
    const base = fieldNoise(x, y, t) * (0.35 + state.entropy * 0.75);
    let impacts = 0;
    for (const impact of terrainImpacts) {
      const dx = x - impact.x;
      const dy = y - impact.y;
      const distance = Math.sqrt(dx * dx + dy * dy);
      const falloff = Math.max(0, 1 - distance / impact.radius);
      const shape = falloff * falloff * (3 - 2 * falloff) * impact.life * impact.force;
      if (impact.kind === "basin") impacts -= shape * 0.9;
      else if (impact.kind === "stabilize") impacts += shape * 0.25;
      else impacts += shape;
    }
    return base + impacts;
  }

  function drawSemanticTerrain(dt) {
    state.terrainPhase += dt * 0.00016 * (0.4 + state.activity);
    const [cx, cy] = center();
    const rows = reducedMotion ? 7 : 13;
    const cols = reducedMotion ? 12 : 24;
    const spanX = internalW * 0.86;
    const spanY = internalH * 0.56;
    const t = state.terrainPhase;
    const calm = state.confidence;
    const alphaBase = 0.018 + state.activity * 0.032;

    for (let r = 0; r < rows; r++) {
      const v = r / Math.max(1, rows - 1);
      const y = cy - spanY * 0.5 + v * spanY;
      ctx.beginPath();
      for (let c = 0; c < cols; c++) {
        const u = c / Math.max(1, cols - 1);
        const x = cx - spanX * 0.5 + u * spanX;
        const h = terrainHeight(x, y, t);
        const perspective = 0.55 + v * 0.45;
        const jagged = 10 + state.entropy * 12;
        const px = x + Math.sin(t + v * 6) * jagged;
        const py = y + h * 34 * perspective + Math.cos(t * 1.7 + u * 4) * 5 * (1 - calm);
        if (c === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      const color = state.weather === "storm" || state.weather === "serpent" ? "235,80,45" : "120,220,185";
      ctx.strokeStyle = `rgba(${color},${alphaBase * (0.55 + v) * (0.7 + state.confidence * 0.4)})`;
      ctx.lineWidth = 0.75 + state.entropy * 1.2;
      ctx.stroke();
    }

    for (let c = 0; c < cols; c += 2) {
      const u = c / Math.max(1, cols - 1);
      const x = cx - spanX * 0.5 + u * spanX;
      ctx.beginPath();
      for (let r = 0; r < rows; r++) {
        const v = r / Math.max(1, rows - 1);
        const y = cy - spanY * 0.5 + v * spanY;
        const h = terrainHeight(x, y, t + 7.3);
        const px = x + Math.sin(t + v * 6) * 10 * state.entropy;
        const py = y + h * 28 * (0.55 + v * 0.45);
        if (r === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      ctx.strokeStyle = `rgba(230,180,110,${alphaBase * 0.45})`;
      ctx.lineWidth = 0.55;
      ctx.stroke();
    }

    for (let i = terrainImpacts.length - 1; i >= 0; i--) {
      const impact = terrainImpacts[i];
      impact.life -= dt * 0.00036;
      if (impact.life <= 0) {
        terrainImpacts.splice(i, 1);
        continue;
      }
      const radius = impact.radius * (1.15 - impact.life * 0.15);
      ctx.beginPath();
      ctx.strokeStyle = `rgba(${impact.color},${impact.life * 0.10})`;
      ctx.lineWidth = impact.kind === "fracture" || impact.kind === "rift" ? 1.7 : 0.9;
      ctx.arc(impact.x, impact.y, radius, 0, Math.PI * 2);
      ctx.stroke();
    }
  }

  function drawAgentSpirits(dt) {
    const [cx, cy] = center();
    const base = Math.min(internalW, internalH);
    for (let idx = 0; idx < agents.length; idx++) {
      const agent = agents[idx];
      // Read charge from kernel cell when available (ecology port).
      let kCharge = agent.charge;
      if (agentsPool && agentsPool.alive[idx]) {
        const b = idx * window.ParticleKernel.FIELDS_PER_CELL;
        kCharge = agentsPool.cells[b + window.ParticleKernel.FIELD.arousal] || agent.charge;
      }
      agent.angle += dt * (0.00008 + kCharge * 0.00022) * (reducedMotion ? 0.25 : 1);
      agent.charge += (0.42 - agent.charge) * 0.006;
      const radius = base * agent.radius * (0.74 + state.activity * 0.18 - (state.confidence - 0.5) * 0.08);
      const wobble = Math.sin(state.time * 0.0012 + agent.angle * 3) * base * 0.015;
      const x = cx + Math.cos(agent.angle) * (radius + wobble);
      const y = cy + Math.sin(agent.angle * 0.91) * radius * 0.62;
      const glow = 0.12 + kCharge * 0.42;

      ctx.beginPath();
      ctx.fillStyle = `rgba(${agent.hue},${glow})`;
      ctx.arc(x, y, 3 + kCharge * 6, 0, Math.PI * 2);
      ctx.fill();

      ctx.beginPath();
      ctx.strokeStyle = `rgba(${agent.hue},${0.06 + kCharge * 0.12})`;
      ctx.lineWidth = 1;
      ctx.arc(x, y, 12 + kCharge * 16, 0, Math.PI * 2);
      ctx.stroke();
    }
  }

  function drawTrails(dt) {
    for (let i = trails.length - 1; i >= 0; i--) {
      const trail = trails[i];
      trail.life -= dt * 0.0008;
      trail.x += trail.vx * dt * 0.06;
      trail.y += trail.vy * dt * 0.06;
      trail.vx += Math.sin(state.time * 0.001 + trail.y * 0.01) * 0.012;
      trail.vy += Math.cos(state.time * 0.001 + trail.x * 0.01) * 0.012;
      if (trail.life <= 0) {
        trails.splice(i, 1);
        continue;
      }
      ctx.beginPath();
      ctx.strokeStyle = `rgba(${trail.color},${trail.life * 0.34})`;
      ctx.lineWidth = trail.width;
      ctx.moveTo(trail.x, trail.y);
      ctx.lineTo(trail.x - trail.vx * 16, trail.y - trail.vy * 16);
      ctx.stroke();
    }
  }

  function drawMemories(dt) {
    for (let i = memories.length - 1; i >= 0; i--) {
      const memory = memories[i];
      memory.life -= dt * 0.00018;
      memory.pulse += dt * 0.002;
      if (memory.life <= 0) {
        memories.splice(i, 1);
        continue;
      }
      const alpha = memory.life * (0.16 + Math.sin(memory.pulse) * 0.05);
      ctx.beginPath();
      ctx.fillStyle = `rgba(150,235,195,${alpha})`;
      ctx.arc(memory.x, memory.y, 2 + memory.z * 3, 0, Math.PI * 2);
      ctx.fill();

      for (let j = i - 1; j >= 0; j--) {
        const other = memories[j];
        const dx = other.x - memory.x;
        const dy = other.y - memory.y;
        const d2 = dx * dx + dy * dy;
        const max = Math.min(internalW, internalH) * 0.22;
        if (d2 < max * max) {
          ctx.beginPath();
          ctx.strokeStyle = `rgba(120,220,185,${0.035 * memory.life})`;
          ctx.lineWidth = 1;
          ctx.moveTo(memory.x, memory.y);
          ctx.lineTo(other.x, other.y);
          ctx.stroke();
        }
      }
    }
  }

  function drawWeather(dt) {
    const storm = state.weather === "storm" || state.weather === "serpent";
    for (let i = weather.length - 1; i >= 0; i--) {
      const bit = weather[i];
      bit.life -= dt * (storm ? 0.0009 : 0.00045);
      bit.vx += Math.sin(state.time * 0.002 + bit.y * 0.02) * bit.spin;
      bit.vy += Math.cos(state.time * 0.002 + bit.x * 0.02) * bit.spin;
      bit.x += bit.vx * dt * 0.12;
      bit.y += bit.vy * dt * 0.12;
      if (bit.life <= 0) {
        weather.splice(i, 1);
        continue;
      }
      const color = storm ? "235,80,45" : "230,180,110";
      ctx.beginPath();
      ctx.fillStyle = `rgba(${color},${bit.life * (storm ? 0.20 : 0.09)})`;
      ctx.arc(bit.x, bit.y, bit.radius, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  let previous = performance.now();
  function frame(now) {
    const dt = Math.min(48, now - previous);
    previous = now;
    state.time = now;
    state.activity += (((now - state.lastEventAt) < 3200 ? 0.72 : 0.16) - state.activity) * 0.012;

    ctx.clearRect(0, 0, state.width, state.height);
    ctx.globalCompositeOperation = "lighter";
    drawSemanticTerrain(dt);
    drawWeather(dt);
    drawMemories(dt);
    drawTrails(dt);
    drawAgentSpirits(dt);

    if (!reducedMotion && Math.random() < 0.025 + state.activity * 0.025) spawnWeatherBurst(1, 0.25 + state.activity * 0.5);
    requestAnimationFrame(frame);
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

  // Also expose direct callable for bridge/registry (idempotent path).
  window.addEventListener("master:visual", (event) => {
    if (window.MASTEREcology && typeof window.MASTEREcology.event === "function") {
      // no-op here; the MASTEREcology.event already routes to ingest
    }
  });

  window.MASTEREcology = {
    state,
    agents,
    memories,
    trails,
    terrainImpacts,
    event: (name, detail = {}) => ingestVisual({ ...detail, name }),
    memory: spawnMemory,
    terrain: spawnTerrainImpact,
    burst: spawnWeatherBurst
  };

  resize();
  for (let i = 0; i < 12; i++) spawnMemory({ provider: "seed" });
  requestAnimationFrame(frame);
})();
