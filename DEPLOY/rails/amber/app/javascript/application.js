// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

if ("serviceWorker" in navigator) navigator.serviceWorker.register("/service-worker")

// Nav swipe-to-reveal
document.addEventListener("turbo:load", () => {
  const nav = document.querySelector("nav");
  if (!nav) return;
  let y0 = 0;
  document.addEventListener("touchstart", e => { y0 = e.touches[0].clientY; }, { passive: true });
  document.addEventListener("touchend", e => {
    const dy = e.changedTouches[0].clientY - y0;
    if (dy > 40) nav.classList.add("nav-visible");
    else if (dy < -40) nav.classList.remove("nav-visible");
  }, { passive: true });
});
