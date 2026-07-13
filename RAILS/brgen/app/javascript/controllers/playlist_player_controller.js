import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "audio", "waveform", "scrub", "scrubFill", "playBtn",
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
    this.#refreshCommentsList()
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
