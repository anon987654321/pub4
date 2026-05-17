import "@hotwired/turbo-rails"
import "controllers"

// ── Warp tunnel + city carousel ──────────────────────────────────────────────
// Runs once on first load; canvas/carousel are data-turbo-permanent so they
// survive Turbo navigations without re-initialisation.

const pack32 = (r, g, b, a) => ((a & 255) << 24) | ((b & 255) << 16) | ((g & 255) << 8) | (r & 255);
const motionScale = () => (typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches) ? 0.35 : 1;
const isLowEnd = (navigator.hardwareConcurrency && navigator.hardwareConcurrency <= 2) || (navigator.deviceMemory && navigator.deviceMemory <= 2);
const DPR = Math.min(2, window.devicePixelRatio || 1);

class SimpleCarousel {
  constructor(el, ms = 2800) {
    this.slides = Array.from(el.querySelectorAll(".carousel-slide"));
    this.i = 0; this.n = this.slides.length;
    if (this.n > 1) setInterval(() => this.next(), ms);
  }
  next() {
    this.slides[this.i].classList.remove("active");
    this.i = (this.i + 1) % this.n;
    this.slides[this.i].classList.add("active");
  }
}

class PixelTunnel {
  constructor(c) {
    this.ctx = c; this.w = 0; this.h = 0; this.s = 1;
    this.imageData = null; this.u32 = null; this.BLACK32 = 0;
    this.fov = 250; this.speed = 0.75;
    this.segments = isLowEnd ? 32 : 48;
    this.baseRadius = 75; this.zStep = isLowEnd ? 6 : 4;
    this.particles = []; this.centers = []; this.time = 0;
    this.mouse = { x: 0, y: 0, down: false, active: false };
    this.stars = []; this.bassWobble = 0;
  }

  resize(w, h, s) {
    this.w = w; this.h = h; this.s = s;
    this.ctx.fillStyle = "#000"; this.ctx.fillRect(0, 0, w, h);
    this.imageData = this.ctx.getImageData(0, 0, w, h);
    this.u32 = new Uint32Array(this.imageData.data.buffer);
    const t = new Uint8ClampedArray(4); t[3] = 255;
    this.BLACK32 = new Uint32Array(t.buffer)[0];
    this.stars = [];
    for (let i = 0; i < 80; i++) this.stars.push({ x: (Math.random() - 0.5) * w * 2, y: (Math.random() - 0.5) * h * 2, z: Math.random() * this.fov * 2 - this.fov, brightness: Math.random() * 0.5 + 0.5 });
    this.init();
  }

  drawLine32(x1, y1, x2, y2, c) {
    let dx = Math.abs(x2 - x1), dy = Math.abs(y2 - y1), sx = x1 < x2 ? 1 : -1, sy = y1 < y2 ? 1 : -1, err = dx - dy, lx = x1, ly = y1;
    for (;;) {
      if (lx > 0 && lx < this.w && ly > 0 && ly < this.h) this.u32[lx + ly * this.w] = c;
      if (lx === x2 && ly === y2) break;
      const e2 = 2 * err;
      if (e2 > -dy) { err -= dy; lx += sx; }
      if (e2 < dx) { err += dx; ly += sy; }
    }
  }

  getCirclePos(cx, cy, r, i, s) {
    const a = i * (Math.PI * 2 / s) + this.time + (this.bassWobble || 0) * 0.1;
    return { x: cx + Math.cos(a) * r, y: cy + Math.sin(a) * r };
  }

  init() {
    this.particles = []; this.centers = [];
    const w1 = Math.random() * this.w, h1 = Math.random() * this.h; let c = 0;
    for (let z = -this.fov; z < this.fov; z += this.zStep) {
      this.centers.push({ x: ((this.w / 2) - w1) * (c / 15) + this.w / 2, y: ((this.h / 2) - h1) * (c / 15) + this.h / 2 }); c++;
      const row = [];
      for (let i = 0; i < this.segments; i++) {
        const p = this.getCirclePos(0, 0, this.baseRadius, i, this.segments);
        row.push({ x: p.x, y: p.y, z, x2d: 0, y2d: 0, radius: this.baseRadius, radiusAudio: this.baseRadius, index: i, segments: this.segments, centerX: 0, centerY: 0 });
      }
      this.particles.push(row);
    }
  }

  frame(a) {
    const m = motionScale();
    this.bassWobble = this.bassWobble * 0.92 + (a?.bass || 0) * (a?.beat || 0) * 0.08;
    this.u32.fill(this.BLACK32);

    for (const star of this.stars) {
      star.z -= this.speed * 2 * m;
      if (star.z < -this.fov) { star.z += this.fov * 2; star.x = (Math.random() - 0.5) * this.w * 2; star.y = (Math.random() - 0.5) * this.h * 2; }
      const sc = this.fov / (this.fov + star.z), sx = (this.w / 2 + star.x * sc) | 0, sy = (this.h / 2 + star.y * sc) | 0;
      const br = (star.brightness * (1 - star.z / this.fov) * 180) | 0;
      if (sx > 0 && sx < this.w && sy > 0 && sy < this.h) this.u32[sx + sy * this.w] = pack32(br * 0.3, br * 0.5, br, 255);
    }

    const l = this.particles.length; let s = false;
    for (let i = 0; i < l; i++) {
      const row = this.particles[i], rowBack = i > 0 ? this.particles[i - 1] : null, center = this.centers[i];
      if (this.mouse.active) {
        center.x = (this.w / 2 + this.mouse.x / this.s) * ((row[0].z - this.fov) / 500) + this.w / 2;
        center.y = (this.h / 2 + this.mouse.y / this.s) * ((row[0].z - this.fov) / 500) + this.h / 2;
      } else { center.x += (this.w / 2 - center.x) * 0.015; center.y += (this.h / 2 - center.y) * 0.015; }
      const f = (a?.average || 0) * 64 + (a?.beat ? 8 : 0);
      if ((this.baseRadius + f) * (this.fov / (this.fov + row[0].z)) < 0.15) continue;
      for (let j = 0; j < row.length; j++) {
        const p = row[j], z = this.fov / (this.fov + p.z);
        p.x2d = p.x * z + center.x; p.y2d = p.y * z + center.y; p.radiusAudio = p.radius + f;
        p.z -= this.speed * m; if (p.z < -this.fov) { p.z += this.fov * 2; s = true; }
        const n = this.getCirclePos(p.centerX, p.centerY, p.radiusAudio, p.index, p.segments); p.x = n.x; p.y = n.y;
      }
      const d = i / Math.max(1, l - 1), bt = a?.beat || 0, av = a?.average || 0.45, bs = a?.bass || 0.5;
      const col = pack32(Math.round((20 + 60 * d + bt * 30) / 8) * 8, Math.round((40 + 120 * av) / 8) * 8, Math.round((180 * bs + 75 * (a?.high || 0.35)) / 8) * 8, 255);
      for (let j = 1; j < row.length; j++) this.drawLine32(row[j].x2d | 0, row[j].y2d | 0, row[j - 1].x2d | 0, row[j - 1].y2d | 0, col);
      if (row.length > 2) this.drawLine32(row[row.length - 1].x2d | 0, row[row.length - 1].y2d | 0, row[0].x2d | 0, row[0].y2d | 0, col);
      if (i > 0 && i < l - 1 && rowBack) for (let j = 0; j < row.length; j++) this.drawLine32(row[j].x2d | 0, row[j].y2d | 0, rowBack[j].x2d | 0, rowBack[j].y2d | 0, col);
    }
    if (s) this.particles = this.particles.sort((a, b) => b[0].z - a[0].z);
    this.time += 0.005 * m;

    const cx = this.w / 2, cy = this.h / 2, beat = a?.beat || 0;
    const glowR = 2 + beat * 1.5, glowCol = pack32(80, 200, 160, 255);
    for (let dx = -glowR; dx <= glowR; dx++) for (let dy = -glowR; dy <= glowR; dy++) if (dx * dx + dy * dy <= glowR * glowR) { const px = (cx + dx) | 0, py = (cy + dy) | 0; if (px > 0 && px < this.w && py > 0 && py < this.h) this.u32[px + py * this.w] = glowCol; }
    this.ctx.putImageData(this.imageData, 0, 0);
  }
}

// Synthetic beat data (no audio needed for visual effect)
let _bp = 0, _be = 0;
const syntheticData = () => {
  _bp += 0.08 * motionScale();
  const b = 0.5 + 0.4 * Math.sin(_bp * 0.8), mid = 0.45 + 0.35 * Math.sin(_bp * 1.2 + 0.7), h = 0.35 + 0.35 * Math.sin(_bp * 1.8 + 1.2);
  const beat = Math.sin(_bp) > 0.8 ? 1 : 0; _be = _be * 0.94 + (beat ? 0.4 : 0) * 0.06;
  return { bass: b, mid, high: h, average: (b + mid + h) / 3, beat: _be };
};

let tunnel, SCALE = 1, lastT = 0;

function initTunnel() {
  const canvas = document.getElementById("tunnel-canvas");
  if (!canvas || canvas.__tunnelInit) return;
  canvas.__tunnelInit = true;

  const ctx = canvas.getContext("2d", { alpha: false, willReadFrequently: true }) || canvas.getContext("2d");
  tunnel = new PixelTunnel(ctx);

  const sizeCanvas = () => {
    SCALE = Math.max(0.5, Math.min(2, Math.min(2, DPR) * (isLowEnd ? 0.8 : 1)));
    const w = Math.floor(window.innerWidth * SCALE), h = Math.floor(window.innerHeight * SCALE);
    canvas.width = w; canvas.height = h;
    canvas.style.width = window.innerWidth + "px"; canvas.style.height = window.innerHeight + "px";
    tunnel.resize(w, h, SCALE);
  };
  sizeCanvas();
  window.addEventListener("resize", () => { clearTimeout(window.__rzT); window.__rzT = setTimeout(sizeCanvas, 80); });

  // Canvas fills the viewport (position:fixed; inset:0) so clientX === canvas X.
  // Listen on window so app-shell (z-index:10) doesn't swallow the events.
  window.addEventListener("mousemove", e => { if (!tunnel) return; tunnel.mouse = { x: e.clientX * SCALE, y: e.clientY * SCALE, down: tunnel.mouse.down, active: true }; }, { passive: true });
  window.addEventListener("mouseleave", () => { if (!tunnel) return; tunnel.mouse.active = false; tunnel.mouse.down = false; });

  const animate = () => {
    const n = performance.now();
    if (!document.hidden && n - lastT >= 16) { tunnel.frame(syntheticData()); lastT = n; }
    requestAnimationFrame(animate);
  };
  animate();
}

function updateCarouselPrefix() {
  const el = document.getElementById("cityCarousel");
  if (!el) return;
  const slides = el.querySelectorAll(".carousel-slide");
  slides.forEach(s => { if (!s.dataset.base) s.dataset.base = s.textContent.trim(); });
  const parts = location.hostname.split(".");
  const prefix = parts.length >= 3 && parts[0] !== "www" ? parts[0] + "." : "";
  slides.forEach(s => { s.textContent = prefix + s.dataset.base; });
}

function initCarousel() {
  const el = document.getElementById("cityCarousel");
  if (!el || el.__carouselInit) return;
  el.__carouselInit = true;
  new SimpleCarousel(el);
  updateCarouselPrefix();
}

function initSplash() {
  const splash = document.getElementById("splash");
  if (!splash || splash.__splashInit) return;
  splash.__splashInit = true;

  const dismiss = () => {
    if (splash.hidden) return;
    splash.style.pointerEvents = "none";
    splash.classList.add("ack");
    const h2 = splash.querySelector("h2");
    if (h2) h2.classList.add("clicked");
    setTimeout(() => { splash.hidden = true; splash.classList.remove("ack"); }, 220);
  };

  splash.addEventListener("click", e => { e.stopPropagation(); dismiss(); });
  splash.addEventListener("keydown", e => { if (e.code === "Enter" || e.code === "Space") { e.preventDefault(); dismiss(); } });
  splash.focus();
}

document.addEventListener("DOMContentLoaded", () => {
  initTunnel();
  initCarousel();
  initSplash();
});

// Re-run splash + carousel prefix on Turbo page loads (tunnel/carousel persist via data-turbo-permanent)
document.addEventListener("turbo:load", () => {
  initSplash();
  updateCarouselPrefix();
});
