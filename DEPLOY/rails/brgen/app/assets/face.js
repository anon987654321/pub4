let tunnel, SCALE = 1, lastT = 0;

if (window.Turbo?.config?.drive) Turbo.config.drive.progressBarDelay = 100;

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

function syncStandaloneMode() {
  const standalone = window.matchMedia("(display-mode: standalone)").matches;
  document.documentElement.dataset.displayMode = standalone ? "standalone" : "browser";
  document.querySelectorAll("nav").forEach(nav => nav.classList.toggle("nav-visible", standalone));
}

document.addEventListener("DOMContentLoaded", () => {
  initTunnel();
  initCarousel();
  initSplash();
  syncStandaloneMode();
});

// Re-run splash + carousel prefix on Turbo page loads (tunnel/carousel persist via data-turbo-permanent)
document.addEventListener("turbo:load", () => {
  initSplash();
  updateCarouselPrefix();
  syncStandaloneMode();
});


