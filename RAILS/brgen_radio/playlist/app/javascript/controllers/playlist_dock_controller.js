import { Controller } from "@hotwired/stimulus"

// Holds a playing audio element across Turbo navigation (playlist/shared/_dock,
// data-turbo-permanent). playlist_player dispatches playlist-dock:adopt with
// its audio element before the page is replaced, and playlist-dock:release
// when a player on the new page starts playing, so two tracks never overlap.
export default class extends Controller {
  static targets = ["title", "toggle"]
  static values = { playLabel: String, pauseLabel: String }

  adopt(event) {
    const { audio, title, artist } = event.detail || {}
    if (!audio) return

    this.close()
    // Moved, not copied: the element keeps playing because it is back in the
    // document before the browser checks whether to pause a removed one.
    audio.removeAttribute("data-playlist-player-target")
    this.element.append(audio)
    this.audio = audio

    this.sync = () => this.#syncToggle()
    audio.addEventListener("play", this.sync)
    audio.addEventListener("pause", this.sync)
    audio.addEventListener("ended", this.sync)

    if (this.hasTitleTarget) this.titleTarget.textContent = [title, artist].filter(Boolean).join(" — ")
    this.element.hidden = false
    this.#syncToggle()
  }

  toggle() {
    if (!this.audio) return
    if (this.audio.paused) this.audio.play()?.catch?.(() => this.#syncToggle())
    else this.audio.pause()
  }

  close() {
    if (this.audio) {
      this.audio.pause()
      this.audio.remove()
      this.audio = null
    }
    this.element.hidden = true
  }

  #syncToggle() {
    if (!this.hasToggleTarget || !this.audio) return
    this.toggleTarget.textContent = this.audio.paused ? this.playLabelValue : this.pauseLabelValue
  }
}
