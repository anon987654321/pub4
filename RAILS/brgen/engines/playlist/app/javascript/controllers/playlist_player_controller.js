import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "audio", "waveform", "scrub", "scrubFill", "playBtn", "playIcon",
    "currentTime", "duration", "title", "artist", "artwork", "queueItem", "embed",
    "commentForm", "commentInput", "commentsList"
  ]

  static values = {
    src: String,
    embed: String,
    title: String,
    artist: String,
    artwork: String,
    trackId: String,
    color: { type: String, default: "#00d4ff" },
    comments: { type: Array, default: [] },
    trackComments: { type: Object, default: {} },
    showArtwork: { type: Boolean, default: true },
    compact: { type: Boolean, default: false },
    hideBranding: { type: Boolean, default: false }
  }

  #resizeWaveform

  connect() {
    this.playing = false
    this.peaks = this.#peaksForTrack(this.trackIdValue || "default")
    this.#resizeWaveform = this.#drawWaveform.bind(this)
    window.addEventListener("resize", this.#resizeWaveform)

    if (this.hasAudioTarget) {
      this.audioTarget.addEventListener("timeupdate", () => this.#tick())
      this.audioTarget.addEventListener("loadedmetadata", () => this.#tick())
      this.audioTarget.addEventListener("ended", () => this.#onEnded())
      this.audioTarget.addEventListener("play", () => this.#recordListenOnce(), { once: true })
    }
    this.#setupMediaSession()

    if (this.hasSrcValue && this.hasAudioTarget && !this.audioTarget.src) {
      this.audioTarget.src = this.srcValue
    }

    this.#drawWaveform(0)
    this.#tick()

    if (!this.showArtworkValue && this.hasArtworkTarget) {
      const wrap = this.artworkTarget.closest(".playlist-artwork-wrap")
      if (wrap) wrap.style.display = "none"
      else this.artworkTarget.hidden = true
    }
    if (this.compactValue) {
      this.element.classList.add("is-compact")
    }
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

  // Stop is not pause. Pause leaves the needle where it was; stop returns to the
  // start, which is the distinction the two buttons exist to express.
  stop() {
    if (!this.hasAudioTarget) return
    this.audioTarget.pause()
    this.audioTarget.currentTime = 0
    this.playing = false
    this.#syncPlayButton()
    this.#tick()
  }

  previous() {
    this.#step(-1)
  }

  next() {
    this.#step(1)
  }

  // Volume from a range input, 0..1. Kept off the audio element's own default so
  // a muted-by-slider state survives a track change, which #step triggers.
  setVolume(event) {
    const value = Math.min(1, Math.max(0, Number(event.currentTarget.value)))
    this.volume = value
    if (this.hasAudioTarget) this.audioTarget.volume = value
  }

  // Walk the queue by delta and hand the neighbouring row to load(), rather than
  // reimplementing what load() already does with the row's data-*-param
  // attributes. Wraps at both ends: a transport bar with a dead button at the
  // last track is the shape this repo has been removing all day.
  #step(delta) {
    if (!this.hasQueueItemTarget) return
    const items = this.queueItemTargets
    if (!items.length) return

    const current = items.findIndex((el) => el.classList.contains("is-active"))
    const from = current >= 0 ? current : 0
    const target = items[(from + delta + items.length) % items.length]
    if (!target) return

    // load() already starts playback and moves is-active; calling play() here
    // too would be a second start on the same element.
    this.load({ currentTarget: target })
  }

  scrub(event) {
    if (!this.hasAudioTarget || !this.audioTarget.duration) return
    const rect = this.scrubTarget.getBoundingClientRect()
    const ratio = Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width))
    this.audioTarget.currentTime = ratio * this.audioTarget.duration
    this.#tick()
  }

  // The scrubber carried role="slider" with aria-valuemin/max/now and no way to
  // reach or move it from a keyboard: a control that announces itself to a screen
  // reader as a slider and then does not behave like one is worse than an
  // unlabelled div, because the label is a promise. role="slider" obliges arrow
  // keys, Home and End — this is that half.
  //
  // Written against currentTime rather than the aria value, so the audio element
  // stays the single source of position and #tick keeps aria-valuenow honest.
  scrubKey(event) {
    if (!this.hasAudioTarget || !this.audioTarget.duration) return

    const duration = this.audioTarget.duration
    const step = event.shiftKey ? duration / 10 : 5
    let next = null

    switch (event.key) {
      case "ArrowRight":
      case "ArrowUp":
        next = this.audioTarget.currentTime + step
        break
      case "ArrowLeft":
      case "ArrowDown":
        next = this.audioTarget.currentTime - step
        break
      case "Home":
        next = 0
        break
      case "End":
        next = duration
        break
      case " ":
      case "Enter":
        this.toggle()
        event.preventDefault()
        return
      default:
        return
    }

    this.audioTarget.currentTime = Math.min(duration, Math.max(0, next))
    this.#tick()
    // Arrow keys scroll the page by default, which is the opposite of seeking.
    event.preventDefault()
  }

  waveformScrub(event) {
    if (!this.hasAudioTarget || !this.audioTarget.duration) return
    const rect = this.waveformTarget.getBoundingClientRect()
    const ratio = Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width))
    this.audioTarget.currentTime = ratio * this.audioTarget.duration
    this.#tick()
  }

  seekToComment(event) {
    if (!this.hasAudioTarget || !this.audioTarget.duration) return
    const time = parseFloat(event.currentTarget.dataset.time) || 0
    this.audioTarget.currentTime = time
    this.#tick()
  }

  addComment() {
    if (!this.hasCommentFormTarget || !this.hasAudioTarget) return
    this.pendingCommentTime = this.audioTarget.currentTime || 0
    this.commentFormTarget.hidden = false
    this.commentInputTarget.focus()
    this.commentInputTarget.placeholder = `Comment at ${this.#formatTime(this.pendingCommentTime)}`
  }

  submitComment() {
    if (!this.hasCommentInputTarget || this.pendingCommentTime == null) return
    const body = this.commentInputTarget.value.trim()
    if (!body) return
    const trackId = this.trackIdValue
    if (!trackId) return

    // Stimulate the reflex
    this.stimulate('PlaylistTimestampedComments#create', {
      track_id: trackId,
      body: body,
      timestamp: this.pendingCommentTime
    })

    this.cancelComment()
    // Note: model broadcasts append to comments; for full update, may need turbo or reload
  }

  cancelComment() {
    if (this.hasCommentFormTarget) {
      this.commentFormTarget.hidden = true
      this.commentInputTarget.value = ''
      this.commentInputTarget.placeholder = 'Comment at this time...'
    }
    this.pendingCommentTime = null
  }

  load(event) {
    const item = event.currentTarget
    const src = item.dataset.playlistPlayerSrcParam
    const embed = item.dataset.playlistPlayerEmbedParam
    const title = item.dataset.playlistPlayerTitleParam
    const artist = item.dataset.playlistPlayerArtistParam
    const artwork = item.dataset.playlistPlayerArtworkParam
    const trackId = item.dataset.playlistPlayerTrackIdParam
    const commentsJson = item.dataset.playlistPlayerCommentsParam
    if (!src && !embed) return

    this.srcValue = src
    this.embedValue = embed || ""
    this.titleValue = title || ""
    this.artistValue = artist || ""
    this.artworkValue = artwork || ""
    this.trackIdValue = trackId || ""
    if (commentsJson) {
      try { this.commentsValue = JSON.parse(commentsJson) } catch (e) { /* keep */ }
    }
    this.peaks = this.#peaksForTrack(trackId || src)

    if (src && this.hasAudioTarget) {
      this.audioTarget.src = src
      // Carry the slider's volume across the track change; without this a
      // listener who turned it down gets full volume on the next track.
      if (typeof this.volume === "number") this.audioTarget.volume = this.volume
      this.audioTarget.play()
      this.playing = true
      this.#updateMediaMetadata()
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
    this.#refreshCommentsList()
  }

  // Media Session: lock-screen / headphone / car controls + now-playing metadata.
  // Table stakes for audio on a phone — the player was fully custom but never
  // registered with the OS. Auto-advance means no explicit next/prev handlers.
  #setupMediaSession() {
    if (!("mediaSession" in navigator) || !this.hasAudioTarget) return
    const audio = this.audioTarget
    const handlers = {
      play: () => audio.play(),
      pause: () => audio.pause(),
      seekbackward: (d) => { audio.currentTime = Math.max(0, audio.currentTime - (d.seekOffset || 10)) },
      seekforward: (d) => { audio.currentTime = Math.min(audio.duration || 0, audio.currentTime + (d.seekOffset || 10)) },
      seekto: (d) => { if (d.seekTime != null) audio.currentTime = d.seekTime },
    }
    for (const [action, fn] of Object.entries(handlers)) {
      try { navigator.mediaSession.setActionHandler(action, fn) } catch (e) { /* unsupported */ }
    }
    audio.addEventListener("play", () => { navigator.mediaSession.playbackState = "playing" })
    audio.addEventListener("pause", () => { navigator.mediaSession.playbackState = "paused" })
    if (this.titleValue) this.#updateMediaMetadata()
  }

  #updateMediaMetadata() {
    if (!("mediaSession" in navigator) || !window.MediaMetadata) return
    navigator.mediaSession.metadata = new window.MediaMetadata({
      title: this.titleValue || "brgen playlist",
      artist: this.artistValue || "brgen",
      album: "brgen",
      artwork: this.artworkValue ? [{ src: this.artworkValue, sizes: "512x512", type: "image/jpeg" }] : [],
    })
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
    // The bottom transport bar's button carries both glyphs and swaps them by
    // class, because the footer button below is driven by textContent and the
    // two cannot share a target without one erasing the other's markup.
    if (this.hasPlayIconTarget) {
      const playing = this.hasAudioTarget && !this.audioTarget.paused
      this.playIconTarget.classList.toggle("is-playing", playing)
      this.playIconTarget.setAttribute("aria-pressed", playing ? "true" : "false")
    }
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
      ctx.fillStyle = played ? this.colorValue : "rgba(255, 255, 255, 0.18)"
      ctx.fillRect(x, y, barWidth, barHeight)
    })

    // Draw timestamped comment markers
    if (this.commentsValue && this.commentsValue.length > 0 && this.audioTarget && this.audioTarget.duration) {
      const duration = this.audioTarget.duration
      ctx.fillStyle = "#ffeb3b"
      this.commentsValue.forEach(comment => {
        const time = comment.time || 0
        const idx = Math.floor((time / duration) * this.peaks.length)
        if (idx >= 0 && idx < this.peaks.length) {
          const x = idx * (barWidth + gap)
          ctx.fillRect(x, 0, 2, height)
        }
      })
    }
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

  #recordListenOnce() {
    // Count a listen on play (server de-dupes per listener/duration via model)
    const trackId = this.trackIdValue
    if (!trackId) return
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch("/listens", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token || "",
        "Accept": "application/json"
      },
      body: JSON.stringify({ track_id: trackId })
    }).catch(() => { /* silent for public/embeds */ })
  }

  #refreshCommentsList() {
    if (!this.hasCommentsListTarget) return
    const list = this.commentsListTarget
    // Clear previous dynamic children (keep h3)
    Array.from(list.querySelectorAll(".playlist-comment")).forEach(el => el.remove())
    const h3 = list.querySelector("h3")
    ;(this.commentsValue || []).forEach(c => {
      const div = document.createElement("div")
      div.className = "playlist-comment"
      div.dataset.time = c.time || 0
      div.setAttribute("data-action", "click->playlist-player#seekToComment")
      div.innerHTML = `<span class="time">${this.#formatTime(c.time || 0)}</span> <span class="text">${(c.text || "").replace(/</g,"&lt;")}</span>`
      list.appendChild(div)
    })
  }
}
