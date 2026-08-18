if (window.Turbo?.config?.drive) Turbo.config.drive.progressBarDelay = 100;

// Carries the current vertical across to the other cities: on dating.brgen.no
// the oshlo.no slide reads dating.oshlo.no. The href has to move with the label
// — it did not, so every slide announced a subdomain and navigated to the apex.
function updateCarouselPrefix() {
  const el = document.getElementById("cityCarousel");
  if (!el) return;
  const slides = el.querySelectorAll(".carousel-slide");
  slides.forEach(s => { if (!s.dataset.base) s.dataset.base = s.textContent.trim(); });
  const parts = location.hostname.split(".");
  const prefix = parts.length >= 3 && parts[0] !== "www" ? parts[0] + "." : "";
  slides.forEach(s => {
    const host = prefix + s.dataset.base;
    s.textContent = host;
    s.href = `https://${host}/`;
  });
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
  initCarousel();
  initSplash();
  syncStandaloneMode();
});

// Re-run splash + carousel prefix on Turbo page loads (carousel persists via data-turbo-permanent)
document.addEventListener("turbo:load", () => {
  initSplash();
  updateCarouselPrefix();
  syncStandaloneMode();
});

