let navRevealBooted = false

export function bootNavReveal() {
  if (navRevealBooted) return
  const nav = document.querySelector("nav")
  if (!nav) return

  navRevealBooted = true
  let y0 = 0

  document.addEventListener("touchstart", (event) => {
    y0 = event.touches[0].clientY
  }, { passive: true })

  document.addEventListener("touchend", (event) => {
    const dy = event.changedTouches[0].clientY - y0
    if (dy > 40) nav.classList.add("nav-visible")
    else if (dy < -40) nav.classList.remove("nav-visible")
  }, { passive: true })
}