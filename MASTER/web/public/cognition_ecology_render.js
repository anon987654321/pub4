(() => {
  "use strict";

  function eco() {
    return window.MASTEREcology;
  }

  function terrainHeight(x, y, t, E) {
    const base = E.fieldNoise(x, y, t) * (0.35 + E.state.entropy * 0.75);
    let impacts = 0;
    for (const impact of E.terrainImpacts) {
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

  function drawSemanticTerrain(dt, E) {
    const { state, ctx, internalW, internalH, reducedMotion } = E;
    state.terrainPhase += dt * 0.00016 * (0.4 + state.activity);
    const [cx, cy] = E.center();
    const battery = document.body?.dataset?.runtimeProfile === "battery";
    const agentHalve = battery || reducedMotion;
    const rows = agentHalve ? 7 : 13;
    const cols = agentHalve ? 12 : 24;
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
        const h = terrainHeight(x, y, t, E);
        const perspective = 0.55 + v * 0.45;
        const jagged = 10 + state.entropy * 12;
        const px = x + Math.sin(t + v * 6) * jagged;
        const py = y + h * 34 * perspective + Math.cos(t * 1.7 + u * 4) * 5 * (1 - calm);
        if (c === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      const storm = state.weather === "storm" || state.weather === "serpent";
      const color = storm ? "180,140,120" : "220,198,168";
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
        const h = terrainHeight(x, y, t + 7.3, E);
        const px = x + Math.sin(t + v * 6) * 10 * state.entropy;
        const py = y + h * 28 * (0.55 + v * 0.45);
        if (r === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      ctx.strokeStyle = `rgba(210,188,158,${alphaBase * 0.45})`;
      ctx.lineWidth = 0.55;
      ctx.stroke();
    }

    for (let i = E.terrainImpacts.length - 1; i >= 0; i--) {
      const impact = E.terrainImpacts[i];
      impact.life -= dt * 0.00036;
      if (impact.life <= 0) {
        E.terrainImpacts.splice(i, 1);
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

  function drawAgentSpirits(dt, E) {
    const { agents, agentsPool, state, ctx, internalW, internalH, reducedMotion } = E;
    const [cx, cy] = E.center();
    const base = Math.min(internalW, internalH);
    for (let idx = 0; idx < agents.length; idx++) {
      const agent = agents[idx];
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
      const sz = (2 + kCharge * 4) | 0;

      ctx.fillStyle = `rgba(${agent.hue},${glow})`;
      ctx.fillRect((x - sz * 0.5) | 0, (y - sz * 0.5) | 0, sz, sz);

      ctx.strokeStyle = `rgba(${agent.hue},${0.06 + kCharge * 0.12})`;
      ctx.lineWidth = 1;
      ctx.strokeRect((x - 6 - kCharge * 8) | 0, (y - 6 - kCharge * 8) | 0, (12 + kCharge * 16) | 0, (12 + kCharge * 16) | 0);
    }
  }

  function drawTrails(dt, E) {
    const { trails, ctx, state } = E;
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

  function drawMemories(dt, E) {
    const { memories, ctx, internalW, internalH } = E;
    for (let i = memories.length - 1; i >= 0; i--) {
      const memory = memories[i];
      memory.life -= dt * 0.00018;
      memory.pulse += dt * 0.002;
      if (memory.life <= 0) {
        memories.splice(i, 1);
        continue;
      }
      const alpha = memory.life * (0.16 + Math.sin(memory.pulse) * 0.05);
      const sz = (2 + memory.z * 3) | 0;
      ctx.fillStyle = `rgba(220,205,175,${alpha})`;
      ctx.fillRect((memory.x - sz * 0.5) | 0, (memory.y - sz * 0.5) | 0, sz, sz);

      for (let j = i - 1; j >= 0; j--) {
        const other = memories[j];
        const dx = other.x - memory.x;
        const dy = other.y - memory.y;
        const d2 = dx * dx + dy * dy;
        const max = Math.min(internalW, internalH) * 0.22;
        if (d2 < max * max) {
          ctx.beginPath();
          ctx.strokeStyle = `rgba(200,185,155,${0.035 * memory.life})`;
          ctx.lineWidth = 1;
          ctx.moveTo(memory.x, memory.y);
          ctx.lineTo(other.x, other.y);
          ctx.stroke();
        }
      }
    }
  }

  function drawWeather(dt, E) {
    const { weather, ctx, state } = E;
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
      const color = storm ? "170,130,115" : "215,192,162";
      const alpha = bit.life * (storm ? 0.20 : 0.09);
      if (bit.kind === "streak") {
        ctx.strokeStyle = `rgba(${color},${alpha})`;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(bit.x, bit.y);
        ctx.lineTo(bit.x - bit.vx * 8, bit.y - bit.vy * 2);
        ctx.stroke();
      } else {
        const sz = Math.max(1, (bit.radius * 2) | 0);
        ctx.fillStyle = `rgba(${color},${alpha})`;
        ctx.fillRect((bit.x - sz * 0.5) | 0, (bit.y - sz * 0.5) | 0, sz, sz);
      }
    }
  }

  let previous = performance.now();
  let ecologyFrameActive = false;
  function ensureEcologyFrame() {
    if (ecologyFrameActive || document.hidden) return;
    ecologyFrameActive = true;
    requestAnimationFrame(frame);
  }

  function frame(now) {
    const E = eco();
    if (!E) {
      if (!document.hidden) requestAnimationFrame(frame);
      else ecologyFrameActive = false;
      return;
    }
    if (document.hidden) {
      previous = now;
      ecologyFrameActive = false;
      return;
    }
    const dt = Math.min(48, now - previous);
    previous = now;
    E.state.time = now;
    E.state.activity += (((now - E.state.lastEventAt) < 3200 ? 0.72 : 0.16) - E.state.activity) * 0.012;

    const focusMode = document.body?.dataset.focusMode === "1";
    const speaking = document.body?.dataset.mode === "speaking";
    let ecologyAlpha = focusMode ? 0.14 : (document.body?.dataset.longSilence === "1" ? 0.55 : 1.0);
    if (speaking) ecologyAlpha *= 0.32;
    E.canvas.style.opacity = String(ecologyAlpha);

    const { ctx, canvas } = E;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.globalCompositeOperation = "lighter";
    drawSemanticTerrain(dt, E);
    drawWeather(dt, E);
    drawMemories(dt, E);
    drawTrails(dt, E);
    drawAgentSpirits(dt, E);

    if (!E.reducedMotion && !speaking && Math.random() < 0.025 + E.state.activity * 0.025) {
      E.spawnWeatherBurst(1, 0.25 + E.state.activity * 0.5);
    }
    if (!document.hidden) requestAnimationFrame(frame);
    else ecologyFrameActive = false;
  }

  function bootEcologyFrame() {
    ensureEcologyFrame();
  }

  if (window._primerFired) {
    bootEcologyFrame();
  } else {
    window.addEventListener("primer:ready", bootEcologyFrame, { once: true });
  }
  window.addEventListener("master:visual", () => ensureEcologyFrame(), { passive: true });
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) ensureEcologyFrame();
  }, { passive: true });
})();