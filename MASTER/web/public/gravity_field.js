(() => {
  "use strict";

  const root = document.documentElement;
  const canvas = document.createElement("canvas");
  canvas.id = "master-gravity-field";
  canvas.setAttribute("aria-hidden", "true");
  canvas.style.cssText = [
    "position:fixed",
    "inset:0",
    "width:100vw",
    "height:100vh",
    "pointer-events:none",
    "z-index:1",
    "opacity:.58"
  ].join(";");
  document.body.appendChild(canvas);

  const ctx = canvas.getContext("2d", { alpha: true });
  if (!ctx) return;

  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const pointer = { x: 0.5, y: 0.46, active: 0 };
  const center = { x: 0.5, y: 0.46, targetX: 0.5, targetY: 0.46 };
  const particles = [];
  const TWO_PI = Math.PI * 2;
  const GOLDEN_ANGLE = 2.399963229728653;

  let width = 1;
  let height = 1;
  let count = 0;
  let activity = 0.08;
  let entropy = 0.20;
  let confidence = 0.82;
  let previous = performance.now();
  let running = false;

  function clamp(value, fallback = 0) {
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(0, Math.min(1, number)) : fallback;
  }

  function hash(index, salt = 0) {
    const value = Math.sin(index * 12.9898 + salt * 78.233) * 43758.5453;
    return value - Math.floor(value);
  }

  function targetCount() {
    if (reduced) return 104;

    const profile = root.dataset.runtimeProfile || "calm";
    const area = width * height;
    if (profile == "battery") return 220;
    if (area < 420000) return 320;
    if (profile == "full" || profile == "crt") return 820;
    return 640;
  }

  function shellTarget(index, now) {
    const radiusJitter = 0.72 + hash(index, 17.0) * 0.25;
    const angle = index * GOLDEN_ANGLE + hash(index, 31.0) * 0.18;
    const breathing = 1
      + Math.sin(now * 0.00019 + index * 0.071) * 0.034
      + Math.sin(now * 0.00051 + index * 0.019) * 0.012;
    const drift = Math.sin(now * 0.00008 + index * 0.013) * 0.018;
    const twist = angle + drift + Math.sin(now * 0.00012 + index * 0.023) * 0.011;

    const rx = Math.min(width * 0.39, height * 0.62);
    const ry = Math.min(height * 0.30, width * 0.55);
    const cx = width * (center.x + (pointer.x - 0.5) * 0.018 * activity);
    const cy = height * (center.y + (pointer.y - 0.46) * 0.018 * activity);

    const x = cx + Math.cos(twist) * rx * radiusJitter * breathing;
    const y = cy + Math.sin(twist) * ry * radiusJitter * breathing;
    const filament = Math.sin(twist * 3.0 + now * 0.00021) * height * 0.010;
    const depth = 0.28 + hash(index, 47.0) * 0.72;

    return {
      x: x + Math.cos(twist * 2.0) * filament,
      y: y + Math.sin(twist * 2.0) * filament * 0.65,
      depth
    };
  }

  function seed() {
    const next = [];
    for (let i = 0; i < count; i++) {
      const home = shellTarget(i, previous);
      const spread = 18 + hash(i, 59.0) * 32;
      const angle = hash(i, 61.0) * TWO_PI;
      next.push({
        index: i,
        x: home.x + Math.cos(angle) * spread,
        y: home.y + Math.sin(angle) * spread,
        vx: 0,
        vy: 0,
        depth: home.depth,
        phase: hash(i, 67.0) * TWO_PI
      });
    }
    particles.length = 0;
    particles.push(...next);
  }

  function resize() {
    width = Math.max(1, innerWidth);
    height = Math.max(1, innerHeight);
    const dpr = reduced ? 1 : Math.min(devicePixelRatio || 1, 1.5);
    canvas.width = Math.max(1, Math.round(width * dpr));
    canvas.height = Math.max(1, Math.round(height * dpr));
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    const nextCount = targetCount();
    if (nextCount != count) {
      count = nextCount;
      seed();
    }
    ensureFrame();
  }

  function signal(detail = {}) {
    entropy = clamp(detail.entropy, entropy);
    confidence = clamp(detail.confidence, confidence);

    const semantic = 0.14 + entropy * 0.44 + (1 - confidence) * 0.34;
    activity = Math.max(activity, clamp(detail.activity, semantic));

    if (Number.isFinite(detail.x)) center.targetX = clamp(detail.x, center.targetX);
    if (Number.isFinite(detail.y)) center.targetY = clamp(detail.y, center.targetY);

    root.dataset.gravityState = "active";
    clearTimeout(signal.timer);
    signal.timer = setTimeout(() => {
      root.dataset.gravityState = "quiet";
    }, 850);
    ensureFrame();
  }

  function pointerMove(event) {
    if (reduced) return;
    pointer.x = event.clientX / Math.max(1, width);
    pointer.y = event.clientY / Math.max(1, height);
    pointer.active = Math.min(1, pointer.active + 0.18);
    activity = Math.min(1, activity + 0.035);
    ensureFrame();
  }

  function pointerLeave() {
    pointer.active *= 0.45;
  }

  function step(now) {
    const dt = Math.min(0.035, Math.max(0.001, (now - previous) / 1000));
    previous = now;

    activity += (0.08 - activity) * dt * 0.62;
    entropy += (0.20 - entropy) * dt * 0.42;
    confidence += (0.82 - confidence) * dt * 0.38;
    pointer.active += (0 - pointer.active) * dt * 2.5;

    center.x += (center.targetX - center.x) * dt * 1.9;
    center.y += (center.targetY - center.y) * dt * 1.9;

    const profile = root.dataset.runtimeProfile || "calm";
    const spring = profile == "battery" ? 3.2 : 4.2 + activity * 1.5;
    const damping = Math.exp(-(profile == "battery" ? 5.8 : 6.4) * dt);
    const pointerRadius = Math.min(220, Math.max(120, Math.min(width, height) * 0.20));

    for (const particle of particles) {
      const target = shellTarget(particle.index, now);
      const dx = target.x - particle.x;
      const dy = target.y - particle.y;

      particle.vx += dx * spring * dt;
      particle.vy += dy * spring * dt;

      const wobble = Math.sin(now * 0.00048 + particle.phase) * (8 + entropy * 16 + activity * 12);
      const distHome = Math.max(30, Math.hypot(dx, dy));
      particle.vx += (-dy / distHome) * wobble * dt;
      particle.vy += (dx / distHome) * wobble * dt;

      if (!reduced && pointer.active > 0.01) {
        const px = pointer.x * width;
        const py = pointer.y * height;
        const pdx = particle.x - px;
        const pdy = particle.y - py;
        const distance = Math.hypot(pdx, pdy);
        if (distance < pointerRadius) {
          const safe = Math.max(8, distance);
          const proximity = 1 - distance / pointerRadius;
          const curve = proximity * proximity;
          const localField = distance < pointerRadius * 0.55 ? 1.0 : -0.22;
          const force = (270 + activity * 360) * curve * localField * particle.depth;
          particle.vx += (pdx / safe) * force * dt;
          particle.vy += (pdy / safe) * force * dt;

          const swirl = 110 * curve * particle.depth * dt;
          particle.vx += (-pdy / safe) * swirl;
          particle.vy += (pdx / safe) * swirl;
        }
      }

      particle.vx *= damping;
      particle.vy *= damping;
      particle.x += particle.vx * dt;
      particle.y += particle.vy * dt;
    }
  }

  function draw() {
    ctx.clearRect(0, 0, width, height);
    const styles = getComputedStyle(root);
    const accent = styles.getPropertyValue("--c-accent").trim() || "rgb(123 140 222)";

    for (const particle of particles) {
      const dx = particle.x - pointer.x * width;
      const dy = particle.y - pointer.y * height;
      const local = reduced ? 0 : Math.max(0, 1 - Math.hypot(dx, dy) / Math.max(width, height));
      const alpha = (0.026 + particle.depth * 0.095) * (0.78 + confidence * 0.22)
        + local * pointer.active * 0.075;

      ctx.globalAlpha = Math.min(0.28, alpha);
      ctx.fillStyle = accent;
      ctx.fillRect(Math.round(particle.x), Math.round(particle.y), 1, 1);
    }
    ctx.globalAlpha = 1;
  }

  function frame(now) {
    running = false;
    if (document.hidden) return;
    step(now);
    draw();
    ensureFrame();
  }

  function ensureFrame() {
    if (running || document.hidden || reduced) return;
    running = true;
    requestAnimationFrame(frame);
  }

  addEventListener("pointermove", pointerMove, { passive: true });
  addEventListener("pointerleave", pointerLeave, { passive: true });
  addEventListener("resize", resize, { passive: true });
  addEventListener("master:visual", (event) => signal(event.detail || {}));
  addEventListener("master:emotion", (event) => signal(event.detail || {}));
  addEventListener("gravity:signal", (event) => signal(event.detail || {}));
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) {
      previous = performance.now();
      ensureFrame();
    }
  }, { passive: true });

  resize();
  if (reduced) draw();
})();