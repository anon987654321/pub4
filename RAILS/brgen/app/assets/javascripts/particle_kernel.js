
// ── City carousel ─────────────────────────────────────────────────────────
// Runs once on first load; carousel is data-turbo-permanent so it survives
// Turbo navigations without re-initialisation.

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

