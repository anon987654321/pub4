import { Controller } from "@hotwired/stimulus"

// Moves the primary navigation run for a mouse, which had no way to move it:
// touch swipes it natively (pan-x and scroll-snap in _brgen_navigation.scss),
// a keyboard scrolls the focused link into view, and a mouse wheel only ever
// scrolled the page underneath.
//
//   wheel   a vertical wheel scrolls the run sideways while it can still move
//           that way; at either end the event is left alone and the page scrolls
//   drag    press and pull; a move under DRAG_THRESHOLD is still a click, so a
//           link opens, and a real drag swallows the click it would end in
//   glide   resting the pointer in the band at either faded edge slides the run
//           toward that side, faster the deeper into the band, stopping at the end
//
// It also marks the ends (data-at-start, data-at-end) so the stylesheet can drop
// the fade on a side that has nothing more to show.
const DRAG_THRESHOLD = 6
const GLIDE_SPEED = 12

export default class extends Controller {
  static values = { edgeBand: { type: Number, default: 72 } }

  connect() {
    this.motion = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.glideSpeed = 0
    this.frame = null
    this.drag = null
    this.swallowClick = false
    this.step = this.step.bind(this)

    this.listeners = [
      ["wheel", (event) => this.wheel(event), { passive: false }],
      ["scroll", () => this.markEnds(), { passive: true }],
      ["pointerdown", (event) => this.pointerDown(event)],
      ["pointermove", (event) => this.pointerMove(event)],
      ["pointerup", (event) => this.pointerUp(event)],
      ["pointercancel", (event) => this.pointerUp(event)],
      ["pointerleave", () => this.stopGlide()],
      ["click", (event) => this.click(event), { capture: true }],
      ["dragstart", (event) => event.preventDefault()],
      ["focusin", (event) => this.reveal(event.target)]
    ]
    this.listeners.forEach(([type, handler, options]) => this.element.addEventListener(type, handler, options))

    this.resizeObserver = new ResizeObserver(() => this.markEnds())
    this.resizeObserver.observe(this.element)
    this.markEnds()
  }

  disconnect() {
    this.listeners.forEach(([type, handler, options]) => this.element.removeEventListener(type, handler, options))
    this.resizeObserver.disconnect()
    this.stopGlide()
  }

  get room() {
    return this.element.scrollWidth - this.element.clientWidth
  }

  markEnds() {
    const left = this.element.scrollLeft
    this.element.toggleAttribute("data-at-start", left <= 1)
    this.element.toggleAttribute("data-at-end", left >= this.room - 1)
  }

  canMove(delta) {
    const left = this.element.scrollLeft
    return delta < 0 ? left > 0 : left < this.room - 1
  }

  wheel(event) {
    if (this.room <= 1 || event.ctrlKey) return

    const delta = Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY
    if (delta === 0 || !this.canMove(delta)) return

    event.preventDefault()
    this.element.scrollBy({ left: delta, behavior: "auto" })
  }

  pointerDown(event) {
    if (event.pointerType !== "mouse" || event.button !== 0 || this.room <= 1) return

    this.drag = { x: event.clientX, left: this.element.scrollLeft, moved: false, id: event.pointerId }
  }

  pointerMove(event) {
    if (event.pointerType !== "mouse") return
    if (!this.drag) {
      this.followEdge(event)
      return
    }

    const distance = event.clientX - this.drag.x
    if (!this.drag.moved) {
      if (Math.abs(distance) < DRAG_THRESHOLD) return
      this.drag.moved = true
      this.stopGlide()
      this.element.setPointerCapture(this.drag.id)
      this.element.toggleAttribute("data-moving", true)
    }
    this.element.scrollLeft = this.drag.left - distance
  }

  pointerUp(event) {
    if (!this.drag) return

    if (this.drag.moved) {
      this.swallowClick = true
      if (this.element.hasPointerCapture(event.pointerId)) this.element.releasePointerCapture(event.pointerId)
      this.element.toggleAttribute("data-moving", false)
    }
    this.drag = null
  }

  // A drag ends on a link; the click it produces is the drag's, not a choice.
  click(event) {
    if (!this.swallowClick) return

    this.swallowClick = false
    event.preventDefault()
    event.stopPropagation()
  }

  followEdge(event) {
    if (this.motion.matches || this.room <= 1) {
      this.stopGlide()
      return
    }

    const box = this.element.getBoundingClientRect()
    // Wider on a wide bar: from md up the wordmark and the sign-in control sit
    // over the outer part of each end, and the pointer only reaches the bar
    // inside them.
    const band = Math.min(Math.max(this.edgeBandValue, box.width * 0.15), box.width / 4)
    const fromStart = event.clientX - box.left
    const fromEnd = box.right - event.clientX
    let speed = 0
    if (fromStart < band) speed = -GLIDE_SPEED * (1 - fromStart / band)
    else if (fromEnd < band) speed = GLIDE_SPEED * (1 - fromEnd / band)

    if (speed === 0 || !this.canMove(speed)) {
      this.stopGlide()
      return
    }

    this.glideSpeed = speed
    this.element.toggleAttribute("data-moving", true)
    if (!this.frame) this.frame = requestAnimationFrame(this.step)
  }

  step() {
    this.frame = null
    if (this.glideSpeed === 0) return

    // At least a whole pixel a frame: scrollLeft rounds, and a shallower step
    // at the inner edge of the band would round to no movement at all.
    const before = this.element.scrollLeft
    this.element.scrollLeft = before + Math.sign(this.glideSpeed) * Math.max(1, Math.abs(this.glideSpeed))
    if (this.element.scrollLeft === before) {
      this.stopGlide()
      return
    }
    this.frame = requestAnimationFrame(this.step)
  }

  stopGlide() {
    this.glideSpeed = 0
    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = null
    if (!this.drag?.moved) this.element.toggleAttribute("data-moving", false)
  }

  reveal(target) {
    const link = target.closest("a")
    if (!link) return

    link.scrollIntoView({ block: "nearest", inline: "nearest", behavior: this.motion.matches ? "auto" : "smooth" })
  }
}
