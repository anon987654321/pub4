import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "audio", "waveform", "scrub", "scrubFill", "playBtn",
    "currentTime", "duration", "title", "artist", "artwork", "queueItem", "embed"
  ]

  static values = {
    src: String,
    embed: String,
    title: String,
    artist: String,
    artwork: String,
    trackId: String
  }

  connect() {
    this.playing = false
    this.peaks = this.#peaksForTrack(this.trackIdValue || "default")
    this.#resizeWaveform = this.#drawWaveform.bind(this)
    window.addEventListener("resize", this.#resizeWaveform)

    if (this.hasAudioTarget) {
      this.audioTarget.addEventListener("timeupdate", () => this.#tick())
      this.audioTarget.addEventListener("loadedmetadata", () => this.#tick())
      this.audioTarget.addEventListener("ended", () => this.#onEnded())
    }

    if (this.hasSrcValue && this.hasAudioTarget && !this.audioTarget.src) {
      this.audioTarget.src = this.srcValue
    }

    this.#drawWaveform(0)
    this.#tick()
  }

  disconnect() {
    window.removeEventListener("resize", this.#resizeWaveform)
  }

  toggle() {
    if (!this.hasAudioTarget || !this.audioTarget.src) return
    if (this.audioTarget.paused) {
      this.audioTarget.play()
      this.playing = true
    } else {
      this.audioTarget.pause()
      this.playing = false
    }
    this.#syncPlayButton()
  }

  scrub(event) {
    if (!this.hasAudioTarget || !this.audioTarget.duration) return
    const rect = this.scrubTarget.getBoundingClientRect()
    const ratio = Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width))
    this.audioTarget.currentTime = ratio * this.audioTarget.duration
    this.#tick()
  }

  waveformScrub(event) {
    if (!this.hasAudioTarget || !this.audioTarget.duration) return
    const rect = this.waveformTarget.getBoundingClientRect()
    const ratio = Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width))
    this.audioTarget.currentTime = ratio * this.audioTarget.duration
    this.#tick()
  }

  load(event) {
    const item = event.currentTarget
    const src = item.dataset.playlistPlayerSrcParam
    const embed = item.dataset.playlistPlayerEmbedParam
    const title = item.dataset.playlistPlayerTitleParam
    const artist = item.dataset.playlistPlayerArtistParam
    const artwork = item.dataset.playlistPlayerArtworkParam
    const trackId = item.dataset.playlistPlayerTrackIdParam
    if (!src && !embed) return

    this.srcValue = src
    this.embedValue = embed || ""
    this.titleValue = title || ""
    this.artistValue = artist || ""
    this.artworkValue = artwork || ""
    this.trackIdValue = trackId || ""
    this.peaks = this.#peaksForTrack(trackId || src)

    if (src && this.hasAudioTarget) {
      this.audioTarget.src = src
      this.audioTarget.play()
      this.playing = true
    } else if (this.hasAudioTarget) {
      this.audioTarget.pause()
      this.audioTarget.removeAttribute("src")
      this.audioTarget.load()
      this.playing = false
    }

    if (this.hasEmbedTarget) {
      this.embedTarget.src = embed || ""
      this.embedTarget.hidden = !embed
    }

    if (this.hasTitleTarget) this.titleTarget.textContent = title || "Untitled"
    if (this.hasArtistTarget) this.artistTarget.textContent = artist || "Unknown artist"
    if (this.hasArtworkTarget && artwork) {
      this.artworkTarget.src = artwork
      this.artworkTarget.hidden = false
    } else if (this.hasArtworkTarget) {
      this.artworkTarget.hidden = true
    }

    this.queueItemTargets.forEach(el => {
      el.classList.toggle("is-active", el === item)
    })

    this.#syncPlayButton()
    this.#drawWaveform(0)
    this.#tick()
  }

  #tick() {
    const audio = this.hasAudioTarget ? this.audioTarget : null
    const duration = audio?.duration || 0
    const current = audio?.currentTime || 0
    const ratio = duration ? current / duration : 0

    if (this.hasCurrentTimeTarget) this.currentTimeTarget.textContent = this.#formatTime(current)
    if (this.hasDurationTarget) this.durationTarget.textContent = this.#formatTime(duration)
    if (this.hasScrubFillTarget) this.scrubFillTarget.style.width = `${ratio * 100}%`
    this.#drawWaveform(ratio)
    this.#syncPlayButton()
  }

  #onEnded() {
    this.playing = false
    this.#syncPlayButton()
    const activeIndex = this.queueItemTargets.findIndex(el => el.classList.contains("is-active"))
    const next = this.queueItemTargets[activeIndex + 1]
    if (next) next.click()
  }

  #syncPlayButton() {
    if (!this.hasPlayBtnTarget) return
    if (this.hasEmbedTarget && !this.embedTarget.hidden) {
      this.playBtnTarget.setAttribute("aria-pressed", "false")
      this.playBtnTarget.textContent = "Open"
      return
    }
    const paused = !this.hasAudioTarget || this.audioTarget.paused
    this.playBtnTarget.setAttribute("aria-pressed", paused ? "false" : "true")
    this.playBtnTarget.textContent = paused ? "Play" : "Pause"
  }

  #drawWaveform(progress = 0) {
    if (!this.hasWaveformTarget) return
    const canvas = this.waveformTarget
    const ctx = canvas.getContext("2d")
    const dpr = window.devicePixelRatio || 1
    const width = canvas.clientWidth
    const height = canvas.clientHeight
    if (!width || !height) return

    canvas.width = Math.floor(width * dpr)
    canvas.height = Math.floor(height * dpr)
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    ctx.clearRect(0, 0, width, height)

    const bars = this.peaks.length
    const gap = 2
    const barWidth = Math.max(2, (width - gap * bars) / bars)
    const playedIndex = Math.floor(progress * bars)

    this.peaks.forEach((peak, index) => {
      const barHeight = Math.max(4, peak * height * 0.88)
      const x = index * (barWidth + gap)
      const y = (height - barHeight) / 2
      const played = index <= playedIndex
      ctx.fillStyle = played ? "#ff5500" : "rgba(255, 255, 255, 0.18)"
      ctx.fillRect(x, y, barWidth, barHeight)
    })
  }

  #peaksForTrack(seed) {
    let hash = 0
    const text = String(seed)
    for (let i = 0; i < text.length; i += 1) {
      hash = ((hash << 5) - hash) + text.charCodeAt(i)
      hash |= 0
    }

    const peaks = []
    for (let i = 0; i < 96; i += 1) {
      hash = (hash * 1664525 + 1013904223) | 0
      const normalized = ((hash >>> 0) % 1000) / 1000
      const envelope = 0.35 + Math.sin(i / 8) * 0.15 + Math.cos(i / 3.5) * 0.1
      peaks.push(Math.min(1, Math.max(0.08, normalized * envelope)))
    }
    return peaks
  }

  #formatTime(seconds) {
    if (!Number.isFinite(seconds)) return "0:00"
    const whole = Math.floor(seconds)
    const min = Math.floor(whole / 60)
    const sec = whole % 60
    return `${min}:${String(sec).padStart(2, "0")}`
  }
}
