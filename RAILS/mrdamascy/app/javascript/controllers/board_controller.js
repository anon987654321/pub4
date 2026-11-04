import { Controller } from "@hotwired/stimulus"

// Staff board: the grid is replaced live by Order broadcasts. A card that
// newly lands in the placed column plays a short chime, so the kitchen
// hears an order without watching the screen; each card's age ticks on
// every half minute.
export default class extends Controller {
  static values = { ageTemplate: String }

  connect() {
    this.known = this.placedIds()
    this.observer = new MutationObserver(() => this.changed())
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.tick()
    this.timer = setInterval(() => this.tick(), 30_000)
  }

  disconnect() {
    this.observer.disconnect()
    clearInterval(this.timer)
  }

  changed() {
    const now = this.placedIds()
    if ([...now].some((id) => !this.known.has(id))) this.chime()
    this.known = now
  }

  placedIds() {
    const cards = this.element.querySelectorAll('[data-board-column="placed"] [data-order-id]')
    return new Set([...cards].map((card) => card.dataset.orderId))
  }

  // Text is written only when it changes, so the observer above is not fed
  // by its own ticks.
  tick() {
    this.element.querySelectorAll("time[data-placed-at]").forEach((time) => {
      const minutes = Math.max(0, Math.floor((Date.now() - Date.parse(time.dateTime)) / 60_000))
      const text = this.ageTemplateValue.replace("%{minutes}", minutes)
      if (time.textContent !== text) time.textContent = text
    })
  }

  chime() {
    const Context = window.AudioContext || window.webkitAudioContext
    if (!Context) return

    const audio = new Context()
    const tone = audio.createOscillator()
    const volume = audio.createGain()
    tone.frequency.value = 880
    volume.gain.value = 0.15
    tone.connect(volume).connect(audio.destination)
    tone.start()
    tone.stop(audio.currentTime + 0.25)
  }
}
