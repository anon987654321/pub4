(() => {
  "use strict";
  // The many become one: dots drift as a field, then settle into the face, and one mark stays solid.
  // A prototype beside the live face (face_stipple_system.js); nothing here is wired into it.
  const canvas = document.getElementById("field");
  const ctx = canvas.getContext("2d");
  const ui = Object.fromEntries(["replay", "condense", "level", "solo"].map((id) => [id, document.getElementById(id)]));
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const COUNT = 2600;
  const SETTLE_MS = 5200;
  const rand = (i, salt) => { const v = Math.sin(i * 12.9898 + salt * 78.233) * 43758.5453; return v - Math.floor(v); };

  // Face zones in unit space (x, y in -1..1), the same layout the live stipple samples.
  function target(i) {
    const q = rand(i, 1), r = rand(i, 2), side = rand(i, 3) < 0.5 ? -1 : 1;
    if (q < 0.17) { const a = r * Math.PI * 2, rad = 0.075 + rand(i, 4) * 0.04; return { x: side * 0.31 + Math.cos(a) * rad, y: -0.12 + Math.sin(a) * rad * 0.7, zone: "eye", side }; }
    if (q < 0.29) { const a = Math.PI * (0.14 + r * 0.72); return { x: side * (0.30 + r * 0.11), y: -0.34 + Math.cos(a) * 0.05, zone: "brow", side }; }
    if (q < 0.40) { const a = r * Math.PI * 2; return { x: Math.cos(a) * (0.21 + 0.045 * Math.sin(a * 2)), y: 0.40 + Math.sin(a) * 0.06, zone: "mouth", side }; }
    if (q < 0.50) return { x: (rand(i, 6) - 0.5) * 0.045, y: -0.1 + r * 0.38, zone: "nose", side };
    // Skin and rim fill an oval head: radius by the square root keeps the density even.
    const angle = rand(i, 7) * Math.PI * 2, radius = Math.sqrt(r), rim = radius > 0.9;
    return { x: Math.cos(angle) * radius * 0.73, y: Math.sin(angle) * radius * 0.91, zone: rim ? "rim" : "skin", side };
  }

  const dots = Array.from({ length: COUNT }, (_, i) => {
    const t = target(i);
    // The solo mark is one eye, left of centre: a single solid disc among the stipple.
    const solo = t.zone === "eye" && t.side < 0 && rand(i, 11) < 0.9;
    return { ...t, solo, sx: rand(i, 20) * 2 - 1, sy: rand(i, 21) * 2 - 1, delay: rand(i, 22) * 0.35, ph: rand(i, 23) * 6.283, size: 0.7 + rand(i, 24) * 1.1 };
  });

  let started = performance.now();
  // ?condense=0..1 pins the field, for a still frame; ?level=0..1 pins the mouth.
  const query = new URLSearchParams(window.location.search);
  let manual = query.has("condense") ? Number(query.get("condense")) : null;
  if (query.has("level")) ui.level.value = query.get("level");
  ui.replay.onclick = () => { manual = null; ui.condense.value = 0; started = performance.now(); };
  if (manual !== null) ui.condense.value = manual;
  ui.condense.oninput = () => { manual = Number(ui.condense.value); };

  const ease = (t) => t * t * (3 - 2 * t);
  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = canvas.clientWidth * dpr; canvas.height = canvas.clientHeight * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  window.addEventListener("resize", resize); resize();

  function frame(now) {
    const w = canvas.clientWidth, h = canvas.clientHeight, s = Math.min(w, h) * 0.46, cx = w / 2, cy = h / 2;
    const progress = reduced ? 1 : manual ?? Math.min(1, (now - started) / SETTLE_MS);
    if (manual === null) ui.condense.value = progress;
    const level = Number(ui.level.value), soloOn = ui.solo.checked, time = now / 1000;
    const ink = getComputedStyle(document.documentElement).getPropertyValue("--ink");
    const solo = getComputedStyle(document.documentElement).getPropertyValue("--solo");
    ctx.clearRect(0, 0, w, h);
    for (const d of dots) {
      const k = ease(Math.max(0, Math.min(1, (progress - d.delay) / 0.65)));
      const drift = (1 - k) * 0.06;
      const wx = d.sx * 1.15 + Math.sin(time * 0.4 + d.ph) * drift, wy = d.sy * 0.95 + Math.cos(time * 0.37 + d.ph) * drift;
      let tx = d.x, ty = d.y;
      if (d.zone === "mouth") ty += (ty > 0.4 ? 1 : -1) * level * 0.12;
      const x = cx + (wx + (tx - wx) * k) * s, y = cy + (wy + (ty - wy) * k) * s;
      const breath = 1 + Math.sin(time * 1.6 + d.ph) * 0.08 * k;
      if (d.solo && soloOn) {
        ctx.fillStyle = solo; ctx.globalAlpha = 0.55 + 0.45 * k;
        ctx.fillRect(x - 1.6, y - 1.6, 3.2 * breath, 3.2 * breath);
      } else {
        ctx.fillStyle = ink; ctx.globalAlpha = (0.25 + 0.55 * k) * (d.zone === "skin" ? 0.7 : 1);
        ctx.beginPath(); ctx.arc(x, y, d.size * breath, 0, 6.283); ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
