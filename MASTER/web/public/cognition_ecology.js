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

  const memories = [];
  const trails = [];
  const weather = [];
  const MAX_TRAILS = reducedMotion ? 24 : 96;
  const MAX_WEATHER = reducedMotion ? 48 : 180;
  const MAX_MEMORIES = reducedMotion ? 18 : 64;

  function makeCanvas() {
    const node = document.createElement("canvas");
    node.id = "cognition-ecology";
    node.setAttribute("aria-hidden", "true");
    document.body.prepend(node);
    return node;
  }

  function resize() {
    state.width = innerWidth;
    state.height = innerHeight;
    canvas.width = Math.floor(state.width * state.dpr);
    canvas.height = Math.floor(state.height * state.dpr);
    canvas.style.cssText = [
      "position:fixed",
      "inset:0",
      "width:100vw",
      "height:100vh",
      "z-index:-1",
      "pointer-events:none",
      "mix-blend-mode:screen"
    ].join(";");
    ctx.setTransform(state.dpr, 0, 0, state.dpr, 0, 0);
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, Number(value)));
  }

  function center() {
    return [state.width * 0.5, state.height * 0.48];
  }

  function rand(min, max) {
    return min + Math.random() * (max - min);
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

  function drawAgentSpirits(dt) {
    const [cx, cy] = center();
    const base = Math.min(state.width, state.height);
    for (const agent of agents) {
      agent.angle += dt * (0.00008 + agent.charge * 0.00022) * (reducedMotion ? 0.25 : 1);
      agent.charge += (0.42 - agent.charge) * 0.006;
      const radius = base * agent.radius * (0.74 + state.activity * 0.18);
      const wobble = Math.sin(state.time * 0.0012 + agent.angle * 3) * base * 0.015;
      const x = cx + Math.cos(agent.angle) * (radius + wobble);
      const y = cy + Math.sin(agent.angle * 0.91) * radius * 0.62;
      const glow = 0.12 + agent.charge * 0.42;

      ctx.beginPath();
      ctx.fillStyle = `rgba(${agent.hue},${glow})`;
      ctx.arc(x, y, 3 + agent.charge * 6, 0, Math.PI * 2);
      ctx.fill();

      ctx.beginPath();
      ctx.strokeStyle = `rgba(${agent.hue},${0.06 + agent.charge * 0.12})`;
      ctx.lineWidth = 1;
      ctx.arc(x, y, 12 + agent.charge * 16, 0, Math.PI * 2);
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
        const max = Math.min(state.width, state.height) * 0.22;
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
    drawWeather(dt);
    drawMemories(dt);
    drawTrails(dt);
    drawAgentSpirits(dt);

    if (!reducedMotion && Math.random() < 0.025 + state.activity * 0.025) spawnWeatherBurst(1, 0.25 + state.activity * 0.5);
    requestAnimationFrame(frame);
  }

  window.addEventListener("resize", resize, { passive: true });
  window.addEventListener("master:visual", (event) => ingestVisual(event.detail || {}));

  window.MASTEREcology = {
    state,
    agents,
    memories,
    trails,
    event: (name, detail = {}) => ingestVisual({ ...detail, name }),
    memory: spawnMemory,
    burst: spawnWeatherBurst
  };

  resize();
  for (let i = 0; i < 12; i++) spawnMemory({ provider: "seed" });
  requestAnimationFrame(frame);
})();
