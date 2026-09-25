(() => {
  "use strict";

  const root = document.documentElement;
  const canvas = document.createElement("canvas");
  canvas.id = "master-gravity-field";
  canvas.setAttribute("aria-hidden", "true");
  canvas.style.cssText = "position:fixed;inset:0;width:100vw;height:100vh;pointer-events:none;z-index:1;opacity:.62";
  document.body.appendChild(canvas);

  const ctx = canvas.getContext("2d", { alpha: true });
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const points = [];
  const count = reduced ? 90 : 520;
  let w = 1;
  let h = 1;
  let activity = 0.08;
  let entropy = 0.24;
  let confidence = 0.8;
  let ax = 0.5;
  let ay = 0.45;
  let last = performance.now();

  function resize() {
    const d = Math.min(devicePixelRatio || 1, 1.5);
    w = innerWidth;
    h = innerHeight;
    canvas.width = Math.max(1, Math.round(w * d));
    canvas.height = Math.max(1, Math.round(h * d));
    ctx.setTransform(d, 0, 0, d, 0, 0);
  }

  function randomNormal() {
    let a = 0;
    let b = 0;
    while (!a) a = Math.random();
    while (!b) b = Math.random();
    return Math.sqrt(-2 * Math.log(a)) * Math.cos(Math.PI * 2 * b);
  }

  function homePoint(i) {
    const u = (i + 0.5) / count;
    const bend = Math.sin(u * Math.PI * 2.6) * h * 0.075;
    const centerY = h * 0.47 + (u - 0.5) * h * 0.16 + bend;
    const spread = h * (0.075 + 0.10 * Math.sin(u * Math.PI));
    const x = w * (0.11 + u * 0.78);
    return {
      x: x + randomNormal() * w * 0.012,
      y: centerY + randomNormal() * spread,
      z: 0.3 + Math.random() * 0.7,
      phase: Math.random() * Math.PI * 2,
    };
  }

  function seed() {
    points.length = 0;
    for (let i = 0; i < count; i++) {
      const home = homePoint(i);
      points.push({
        x: Math.random() * w,
        y: Math.random() * h,
        vx: (Math.random() - 0.5) * 0.6,
        vy: (Math.random() - 0.5) * 0.6,
        homeX: home.x,
        homeY: home.y,
        z: home.z,
        phase: home.phase,
      });
    }
  }

  function signal(detail = {}) {
    entropy = clamp(detail.entropy, entropy);
    confidence = clamp(detail.confidence, confidence);
    const semantic = 0.16 + entropy * 0.42 + (1 - confidence) * 0.38;
    activity = Math.max(activity, Math.min(1, Number(detail.activity ?? semantic)));
    if (Number.isFinite(detail.x)) ax = detail.x;
    if (Number.isFinite(detail.y)) ay = detail.y;
    root.dataset.gravityState = "active";
    clearTimeout(signal.timer);
    signal.timer = setTimeout(() => {
      root.dataset.gravityState = "quiet";
    }, 900);
  }

  function draw(now) {
    const dt = Math.min(0.04, (now - last) / 1000);
    last = now;

    activity += (0.08 - activity) * dt * 0.55;
    entropy += (0.24 - entropy) * dt * 0.45;
    confidence += (0.8 - confidence) * dt * 0.42;

    ctx.clearRect(0, 0, w, h);

    const accent = getComputedStyle(root).getPropertyValue("--c-accent").trim() || "rgb(123 140 222)";
    const targetX = w * ax;
    const targetY = h * ay;
    const compact = Math.max(0.08, Math.min(1, 0.58 + activity * 0.62));
    const turbulence = 0.65 + entropy * 2.2 + activity * 1.6;

    for (const p of points) {
      const hx = p.homeX;
      const hy = p.homeY;
      const dx = hx - p.x;
      const dy = hy - p.y;
      const homePull = (0.18 + compact * 0.95) * p.z;
      p.vx += dx * homePull * dt;
      p.vy += dy * homePull * dt;

      const pointerDx = targetX - p.x;
      const pointerDy = targetY - p.y;
      const pointerDist = Math.max(80, Math.hypot(pointerDx, pointerDy));
      const pointerForce = (0.02 + activity * 0.11) * p.z / pointerDist;
      p.vx += pointerDx * pointerForce * dt;
      p.vy += pointerDy * pointerForce * dt;

      const drift = Math.sin(now * 0.00055 + p.phase) * turbulence;
      p.vx += (-dy / Math.max(40, Math.hypot(dx, dy))) * drift * dt;
      p.vy += ( dx / Math.max(40, Math.hypot(dx, dy))) * drift * dt;

      p.vx *= 0.986;
      p.vy *= 0.986;
      p.x += p.vx * 72 * dt;
      p.y += p.vy * 72 * dt;

      const marginX = w * 0.04;
      const marginY = h * 0.04;
      if (p.x < -marginX) p.x = w + marginX;
      if (p.x > w + marginX) p.x = -marginX;
      if (p.y < -marginY) p.y = h + marginY;
      if (p.y > h + marginY) p.y = -marginY;

      const distanceFromPointer = Math.hypot(p.x - targetX, p.y - targetY);
      const localActivity = Math.max(0, 1 - distanceFromPointer / Math.max(w, h));
      ctx.globalAlpha = (0.025 + 0.17 * p.z) * (0.72 + 0.28 * confidence) + localActivity * 0.035;
      ctx.fillStyle = accent;
      const size = p.z > 0.78 ? 1.8 : p.z > 0.46 ? 1.3 : 1;
      ctx.fillRect(Math.round(p.x), Math.round(p.y), size, size);
    }

    ctx.globalAlpha = 1;
    if (!reduced) requestAnimationFrame(draw);
  }

  addEventListener("pointermove", (event) => {
    ax = event.clientX / Math.max(1, w);
    ay = event.clientY / Math.max(1, h);
    activity = Math.min(1, activity + 0.025);
    root.dataset.gravityState = "active";
    clearTimeout(signal.timer);
    signal.timer = setTimeout(() => {
      root.dataset.gravityState = "quiet";
    }, 650);
  }, { passive: true });

  addEventListener("resize", () => {
    resize();
    seed();
    if (reduced) draw(performance.now());
  }, { passive: true });

  addEventListener("master:visual", (event) => signal(event.detail || {}));
  addEventListener("gravity:signal", (event) => signal(event.detail || {}));

  resize();
  seed();
  draw(performance.now());
})();

function clamp(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(0, Math.min(1, number)) : fallback;
}
