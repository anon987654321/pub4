// codebase.js — Architecture #15: embodied codebase particle topology.
// Modules are particle clusters. Violations make particles agitated and drift.
// Fixes cause particles to settle back to cluster home.
// Receives master:codebase and master:rule_event CustomEvents from visual_bridge.js.
"use strict";

(() => {
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const canvas = (() => {
    const c = document.createElement("canvas");
    c.id = "codebase-topology";
    c.setAttribute("aria-hidden", "true");
    c.style.cssText = [
      "position:fixed", "inset:0", "width:100vw", "height:100vh",
      "z-index:-2", "pointer-events:none", "mix-blend-mode:screen"
    ].join(";");
    document.body.prepend(c);
    return c;
  })();
  const ctx = canvas.getContext("2d", { alpha: true });

  // ── Layout ──────────────────────────────────────────────────────────────
  let W = innerWidth, H = innerHeight;
  const DPR = Math.min(devicePixelRatio || 1, 2);

  function resize() {
    W = innerWidth; H = innerHeight;
    canvas.width = Math.floor(W * DPR);
    canvas.height = Math.floor(H * DPR);
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    layoutModules();
  }
  addEventListener("resize", resize, { passive: true });

  // ── Module registry ─────────────────────────────────────────────────────
  // Each module = { id, path, home:[x,y], particles:[], violations, status }
  const modules = new Map();
  const PARTICLE_COUNT = reducedMotion ? 6 : 20;

  const MODULE_PALETTE = {
    "lib/master/judge": [255, 180,  80],   // amber — scrutiny
    "lib/master/loop":  [ 80, 200, 160],   // teal  — iteration
    "lib/master/now":   [140, 180, 255],   // blue  — pipeline
    "lib/master/voice": [220, 140, 255],   // violet— personality
    "lib/master/ground":[255, 255, 140],   // gold  — constitution
    "lib/master/reach": [140, 255, 180],   // mint  — tools
    "lib/master/trace": [180, 220, 255],   // sky   — telemetry
    "web/app":          [255, 140, 140],   // rose  — web layer
    "data":             [200, 200, 200],   // grey  — config
    "unknown":          [120, 120, 120],   // dim   — unmapped
  };

  function colorFor(path) {
    for (const [prefix, rgb] of Object.entries(MODULE_PALETTE)) {
      if (path.startsWith(prefix)) return rgb;
    }
    return MODULE_PALETTE["unknown"];
  }

  function layoutModules() {
    const keys = [...modules.keys()];
    const n = keys.length || 1;
    // Treemap-style ring layout: modules orbit the center.
    const cx = W * 0.5, cy = H * 0.5;
    const rings = Math.ceil(Math.sqrt(n / 3));
    let idx = 0;
    for (let ring = 1; ring <= rings && idx < n; ring++) {
      const perRing = Math.ceil(n / rings) * ring;
      const radius  = Math.min(W, H) * 0.12 * ring;
      for (let i = 0; i < perRing && idx < n; i++, idx++) {
        const angle = (2 * Math.PI * i) / perRing;
        const mod = modules.get(keys[idx]);
        mod.home = [cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius];
        mod.particles.forEach(p => { p.tx = mod.home[0]; p.ty = mod.home[1]; });
      }
    }
  }

  function ensureModule(path) {
    if (!modules.has(path)) {
      const rgb = colorFor(path);
      const home = [W * 0.5, H * 0.5];
      const particles = Array.from({ length: PARTICLE_COUNT }, (_, i) => ({
        x: home[0] + (Math.random() - 0.5) * 40,
        y: home[1] + (Math.random() - 0.5) * 40,
        tx: home[0], ty: home[1],
        vx: 0, vy: 0,
        r: Math.random() * 1.2 + 0.4,
        phase: (2 * Math.PI * i) / PARTICLE_COUNT,
        agitation: 0,
      }));
      modules.set(path, { id: path, path, home, particles, violations: 0, status: "clean", rgb });
      layoutModules();
    }
    return modules.get(path);
  }

  // ── Event handlers ───────────────────────────────────────────────────────
  addEventListener("master:codebase", (e) => {
    const data = e.detail || {};
    (data.modules || []).forEach(m => {
      const mod = ensureModule(m.path || "unknown");
      mod.violations = m.violations || 0;
      mod.status     = m.status || (mod.violations > 0 ? "dirty" : "clean");
      // Agitation = violation density, capped at 1.
      const agitation = Math.min(mod.violations / 20, 1.0);
      mod.particles.forEach(p => { p.agitation = agitation; });
    });
  });

  addEventListener("master:rule_event", (e) => {
    const data = e.detail || {};
    // A rule loop fixed something: reduce agitation on relevant clusters.
    if (data.status === "clean") {
      modules.forEach(mod => {
        mod.particles.forEach(p => { p.agitation = Math.max(0, p.agitation - 0.15); });
      });
    }
    if (data.status === "converged") {
      modules.forEach(mod => {
        mod.particles.forEach(p => { p.agitation = Math.max(0, p.agitation - 0.05); });
      });
    }
  });

  // ── Physics ──────────────────────────────────────────────────────────────
  const DAMPING    = 0.88;
  const SPRING     = 0.06;  // pull toward home
  const NOISE_BASE = 0.3;

  function tick(t) {
    modules.forEach(mod => {
      const [hx, hy] = mod.home;
      mod.particles.forEach(p => {
        // Spring force toward cluster home.
        const dx = hx - p.x, dy = hy - p.y;
        p.vx += dx * SPRING;
        p.vy += dy * SPRING;

        // Agitation: random walk amplitude proportional to violation density.
        const amp = NOISE_BASE + p.agitation * 3.5;
        p.vx += (Math.random() - 0.5) * amp;
        p.vy += (Math.random() - 0.5) * amp;

        // Gentle phase-based orbital drift even when clean.
        const phase = p.phase + t * 0.0008;
        p.vx += Math.cos(phase) * 0.08;
        p.vy += Math.sin(phase) * 0.06;

        p.vx *= DAMPING;
        p.vy *= DAMPING;
        p.x  += p.vx;
        p.y  += p.vy;
      });
    });
  }

  // ── Render ───────────────────────────────────────────────────────────────
  function draw(t) {
    ctx.clearRect(0, 0, W, H);

    modules.forEach(mod => {
      const [r, g, b] = mod.rgb;
      const dirty = mod.status !== "clean";

      // Draw soft halo around cluster home.
      const [hx, hy] = mod.home;
      if (!reducedMotion) {
        const grad = ctx.createRadialGradient(hx, hy, 2, hx, hy, 28);
        const alpha = dirty ? 0.12 : 0.05;
        grad.addColorStop(0, `rgba(${r},${g},${b},${alpha})`);
        grad.addColorStop(1, `rgba(${r},${g},${b},0)`);
        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.arc(hx, hy, 28, 0, Math.PI * 2);
        ctx.fill();
      }

      // Draw particles.
      mod.particles.forEach(p => {
        const baseAlpha = dirty
          ? 0.55 + p.agitation * 0.35
          : 0.20 + Math.sin(p.phase + t * 0.001) * 0.08;
        ctx.fillStyle = `rgba(${r},${g},${b},${baseAlpha.toFixed(3)})`;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fill();
      });

      // Draw edges between nearby dirty modules (violation coupling).
      if (dirty && !reducedMotion) {
        modules.forEach(other => {
          if (other === mod || other.status === "clean") return;
          const [ox, oy] = other.home;
          const dist = Math.hypot(hx - ox, hy - oy);
          if (dist > 180) return;
          const alpha = (1 - dist / 180) * 0.06;
          ctx.strokeStyle = `rgba(255,180,80,${alpha.toFixed(3)})`;
          ctx.lineWidth = 0.5;
          ctx.beginPath();
          ctx.moveTo(hx, hy);
          ctx.lineTo(ox, oy);
          ctx.stroke();
        });
      }
    });
  }

  // ── Loop ─────────────────────────────────────────────────────────────────
  let lastT = 0;
  function frame(t) {
    if (!reducedMotion || t - lastT > 500) {
      tick(t);
      draw(t);
      lastT = t;
    }
    requestAnimationFrame(frame);
  }

  resize();
  requestAnimationFrame(frame);
})();
