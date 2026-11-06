// Radio Bergen audio, queue and media-session engine. Kept independent
// from WebGL so playback and spectrum analysis can evolve without owning the
// visual renderer.

import { publishVisual } from "pub4/visual_field"

export const DEFAULT_TRACKS = [
  { title: "Microphone Master [Extended]", id: "9EGHwkDix78", artist: "J Dilla" },
  { title: "Sounds Like Love (Extended)", id: "jnP3tRG-LZs", artist: "J Dilla" },
  { title: "Searchin' (Instrumental)", id: "1XJLtZJ9Ook", artist: "Jay Dee Aka J Dilla" },
  { title: "Get It Together (Instrumental)", id: "t6T-Q6HMbEo", artist: "J-88 (Slum Village)" },
  { title: "Hustle (Instrumental Mix)", id: "zoGTC7uROZE", artist: "J Dilla" },
  { title: "Stupid Lies (Instrumental)", id: "7611GgbJAbM", artist: "J Dilla" },
  { title: "Fantastic (Instrumental)", id: "j0z_-7TfPeM", artist: "J Dilla" },
  { title: "Can I Be Me (Instrumental)", id: "Fo7WoYn_FEs", artist: "J Dilla" }
]

// The original Radio Bergen surface opens on Microphone Master and keeps one
// persistent warped tunnel through the whole eight-track set.
export const OPENING_TRACK_ID = "9EGHwkDix78"

// Preserve the supplied queue order when the legacy opener is absent.
export function initialTrackIndex(tracks, openingTrackId) {
  const opener = tracks.findIndex((track) => track.id === openingTrackId)
  return opener >= 0 ? opener : 0
}

// FFT band edges as a fraction of the spectrum. 2048 bins over ~44.1kHz puts
// bass under ~250Hz, mids to ~2kHz, highs above — the split that makes a kick
// move the ring and a hat shimmer it.
const BAND_BASS = 0.012
const BAND_MID = 0.09

export class AudioEngine {
  constructor({ iframe, trackDisplay, sourceCredit = null, tracks = DEFAULT_TRACKS }) {
    this.iframe = iframe
    this.trackDisplay = trackDisplay
    this.sourceCredit = sourceCredit
    this.tracks = tracks.length ? tracks : DEFAULT_TRACKS
    this.isPlaying = false
    this.currentTrack = initialTrackIndex(this.tracks, OPENING_TRACK_ID)
    this.userInteracted = false
    this.retryCount = 0
    this.maxRetries = 3
    this.bassInfluence = 1.0
    this.midInfluence = 0.8
    this.highInfluence = 0.6
    this.bassLevel = 0
    this.midLevel = 0
    this.highLevel = 0
    this.audioLevel = 0
    this.beat = 0
    this._previousBins = null
    this._previousBass = 0
    this.startTime = 0
    this.audio = null
    this.analyser = null
    this.bins = null
    this.#configureMediaSession()
  }

  #configureMediaSession() {
    if (!("mediaSession" in navigator)) return
    const actions = {
      play: () => {
        this.userInteracted = true
        this.start()
      },
      pause: () => this.stop(),
      nexttrack: () => this.nextTrack(),
      previoustrack: () => this.previousTrack()
    }
    Object.entries(actions).forEach(([action, handler]) => {
      try {
        navigator.mediaSession.setActionHandler(action, handler)
      } catch {
        // Some browsers expose Media Session without every action.
      }
    })
  }

  #syncMediaSession() {
    if (!("mediaSession" in navigator)) return
    const track = this.tracks[this.currentTrack]
    if (!track) return
    const artwork = track.artwork ||
      document.querySelector('meta[property="og:image"]')?.content
    navigator.mediaSession.metadata = new MediaMetadata({
      title: track.title,
      artist: track.artist || "Radio Bergen",
      // A whyp.it track names where it lives, on the lock screen too.
      album: track.whyp_id ? "Radio Bergen · whyp.it" : "Radio Bergen",
      artwork: artwork ? [{ src: artwork }] : []
    })
    navigator.mediaSession.playbackState = this.isPlaying ? "playing" : "paused"
  }

  get currentIsLocal() {
    return Boolean(this.tracks[this.currentTrack]?.src)
  }

  start() {
    if (!this.userInteracted) return false
    this.loadCurrentTrack()
    this.startTime = performance.now()
    this.updateTrackDisplay()
    this.#syncMediaSession()
    return true
  }

  setUserInteracted() { this.userInteracted = true }

  // Built lazily and only once. An AudioContext created before a user gesture
  // starts suspended, and MediaElementSource can only be attached to an element
  // once — attaching per track throws InvalidStateError on the second one.
  #ensureAnalyser() {
    if (this.analyser) return true
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext
      if (!Ctx || !this.audio) return false
      this.audioContext = new Ctx()
      const source = this.audioContext.createMediaElementSource(this.audio)
      this.analyser = this.audioContext.createAnalyser()
      this.analyser.fftSize = 2048
      this.analyser.smoothingTimeConstant = 0.58
      source.connect(this.analyser)
      // Through the analyser to the speakers, not in parallel: a
      // MediaElementSource is *moved* into the graph, so skipping this leaves
      // the page silent while the numbers keep arriving.
      this.analyser.connect(this.audioContext.destination)
      this.bins = new Uint8Array(this.analyser.frequencyBinCount)
      return true
    } catch (err) {
      console.warn("radio_brgen_tunnel: analyser unavailable, playing without it", err)
      this.analyser = null
      return false
    }
  }

  #ensureAudioElement() {
    if (this.audio) return this.audio
    const el = document.createElement("audio")
    el.preload = "auto"
    el.crossOrigin = "anonymous"
    el.addEventListener("ended", () => this.nextTrack())
    el.addEventListener("error", () => {
      this.retryCount += 1
      this.nextTrack()
    })
    this.audio = el
    return el
  }

  loadCurrentTrack() {
    if (this.retryCount >= this.maxRetries) {
      if (this.trackDisplay) this.trackDisplay.textContent = "Audio failed: tap to retry"
      return
    }
    const track = this.tracks[this.currentTrack]
    if (!track) return
    clearTimeout(this._advanceTimer)
    if (track.src) this.#loadLocal(track)
    else if (track.whyp_id) this.#loadWhyp(track)
    else this.#loadYouTube(track)
  }

  #loadLocal(track) {
    // Silence the iframe first or the two sources overlap: the embed keeps
    // playing while an <audio> element starts on top of it.
    if (this.iframe?.src) this.iframe.src = ""
    const el = this.#ensureAudioElement()
    el.src = track.src
    const play = () => {
      this.#ensureAnalyser()
      this.audioContext?.resume?.()
      const p = el.play()
      if (p?.catch) {
        p.catch(() => {
          // Autoplay refused until a gesture; the controller's first-pointer
          // handler calls start() again, so this is not a failure state.
          this.isPlaying = false
        })
      }
    }
    this.isPlaying = true
    play()
  }

  #loadYouTube(track) {
    const origin = encodeURIComponent(window.location.origin)
    this.#loadEmbed(`https://www.youtube.com/embed/${track.id}?autoplay=1&controls=0&disablekb=1&fs=0` +
      `&iv_load_policy=3&modestbranding=1&playsinline=1&rel=0&showinfo=0&origin=${origin}`)
  }

  // whyp.it, the operator's own uploads. The embed takes the track id and its
  // share token and, like YouTube's, says nothing back across the frame, so it
  // advances on the same timer.
  #loadWhyp(track) {
    const id = encodeURIComponent(track.whyp_id)
    const token = encodeURIComponent(track.whyp_token ?? "")
    // The canonical embed; whyp.it 301s its older tracks/embed?id= form here.
    this.#loadEmbed(`https://whyp.it/embeds/track/${id}?token=${token}`)
  }

  #loadEmbed(embedUrl) {
    if (this.audio) this.audio.pause()
    try {
      this.iframe.src = embedUrl
      this.isPlaying = true
      setTimeout(() => {
        if (!this.isPlaying) {
          this.retryCount += 1
          this.loadCurrentTrack()
        }
      }, 1000)
      // No 'ended' event is available across the iframe boundary, so an embed
      // still needs a timer to advance. A local track does not — it fires
      // 'ended' at its real length instead of being cut at three minutes.
      this._advanceTimer = setTimeout(() => {
        if (this.isPlaying) this.nextTrack()
      }, 180000)
    } catch {
      this.retryCount += 1
      setTimeout(() => this.loadCurrentTrack(), 1000)
    }
  }

  previousTrack() {
    this.currentTrack = (this.currentTrack - 1 + this.tracks.length) % this.tracks.length
    this.retryCount = 0
    this.loadCurrentTrack()
    this.updateTrackDisplay()
    this.#syncMediaSession()
    this.publishTrack()
  }

  publishTrack() {
    const track = this.tracks[this.currentTrack]
    publishVisual("radio:track", {
      topology: "tunnel",
      mode: "radio:tunnel",
      activity: 0.72,
      arousal: 0.62,
      confidence: 0.9,
      beat: 0.65,
      name: track?.title || "radio"
    })
  }

  nextTrack() {
    this.currentTrack = (this.currentTrack + 1) % this.tracks.length
    this.retryCount = 0
    this.loadCurrentTrack()
    this.updateTrackDisplay()
    this.#syncMediaSession()
    this.publishTrack()
  }

  getAudioData() {
    if (!this.isPlaying) {
      this.beat *= 0.72
      return { bass: 0, mid: 0, high: 0, average: 0, beat: this.beat, flux: 0 }
    }

    // Real spectrum when we are serving the file ourselves. The sine wave this
    // replaced was not a placeholder for a missing feature — it was the only
    // thing possible while every track was a cross-origin YouTube embed, which
    // is why the tunnel appeared to react to music it could not hear.
    if (this.analyser && this.bins) {
      this.analyser.getByteFrequencyData(this.bins)
      const len = this.bins.length
      const bassEnd = Math.max(1, Math.floor(len * BAND_BASS))
      const midEnd = Math.max(bassEnd + 1, Math.floor(len * BAND_MID))
      let b = 0
      let m = 0
      let h = 0
      let flux = 0
      this._previousBins ||= new Uint8Array(len)
      for (let i = 0; i < len; i++) {
        const value = this.bins[i]
        flux += Math.max(0, value - this._previousBins[i])
        this._previousBins[i] = value
        if (i < bassEnd) b += value
        else if (i < midEnd) m += value
        else h += value
      }
      const bass = Math.min(1, (b / bassEnd / 255) * this.bassInfluence)
      const mid = Math.min(1, (m / (midEnd - bassEnd) / 255) * this.midInfluence)
      // Highs are quiet in absolute terms in most mixes, so a flat normalise
      // leaves the shimmer term permanently near zero.
      const high = Math.min(1, (h / (len - midEnd) / 255) * 2.6 * this.highInfluence)
      const average = (bass + mid + high) / 3
      const spectralFlux = Math.min(1, (flux / len / 255) * 5)
      const bassRise = Math.max(0, bass - this._previousBass)
      const transient = Math.min(1, Math.max(spectralFlux * 1.8, bassRise * 4.5))
      this.beat = Math.max(transient, this.beat * 0.72)
      this._previousBass = bass
      this.bassLevel = bass
      this.midLevel = mid
      this.highLevel = high
      this.audioLevel = average
      return { bass, mid, high, average, beat: this.beat, flux: spectralFlux }
    }

    // YouTube is cross-origin, so the iframe cannot supply an AnalyserNode.
    // Restore the reference's musical motion as a deterministic visual groove:
    // it is not presented to the renderer as a measured spectrum. Local hosted
    // tracks above still use their real FFT values.
    const t = (performance.now() - this.startTime) / 1000
    const bpm = 84 + (this.currentTrack * 5) % 17
    const beatPhase = t * bpm / 60 * Math.PI * 2
    const swing = Math.sin(t * 1.73 + this.currentTrack) * 0.08
    const pocket = Math.cos(t * 0.61 + this.currentTrack * 0.37) * 0.05
    const bass = Math.max(0, Math.min(1, 0.22 + 0.40 * (0.5 + 0.5 * Math.sin(beatPhase + pocket)) + swing)) * this.bassInfluence
    const mid = Math.max(0, Math.min(1, 0.28 + 0.24 * (0.5 + 0.5 * Math.sin(beatPhase * 2.0 + swing)))) * this.midInfluence
    const high = Math.max(0, Math.min(1, 0.10 + 0.22 * (0.5 + 0.5 * Math.sin(beatPhase * 3.0 + pocket)))) * this.highInfluence
    const average = (bass + mid + high) / 3
    const pulse = Math.max(0, Math.sin(beatPhase))
    this.beat = Math.max(pulse * 0.8, this.beat * 0.72)
    this.bassLevel = bass
    this.midLevel = mid
    this.highLevel = high
    this.audioLevel = average
    return { bass, mid, high, average, beat: this.beat, flux: pulse * 0.5, proxy: true }
  }

  updateTrackDisplay(note = null) {
    if (!this.trackDisplay) return
    const track = this.tracks[this.currentTrack]
    if (!track) return
    this.trackDisplay.textContent = [`${track.artist} - ${track.title}`, note].filter(Boolean).join(" · ")
    this.#showSourceCredit(track)
  }

  // While a whyp.it track plays, a visible link to its page there: the music
  // is the operator's, hosted on whyp.it, and the player frame is off-screen,
  // so without this nothing on the page says where it can be followed.
  #showSourceCredit(track) {
    const credit = this.sourceCredit
    if (!credit) return

    credit.hidden = !track.whyp_id
    if (!track.whyp_id) return

    const token = track.whyp_token ? `?token=${encodeURIComponent(track.whyp_token)}` : ""
    credit.href = `https://whyp.it/tracks/${encodeURIComponent(track.whyp_id)}${token}`
  }

  stop() {
    this.isPlaying = false
    if (this.iframe) this.iframe.src = ""
    if (this.audio) this.audio.pause()
    clearTimeout(this._advanceTimer)
    this.#syncMediaSession()
  }
}

// The tunnel's ink, matched to the MASTER face on ai.brgen.no.
//
// Both surfaces are warm now. The face's receding points used to tint
// blue-violet and were changed to a warm ramp the same day this was; the rule
// that matters is that the two surfaces of one site agree, not which end of the
// spectrum they agree on. What is still forbidden here is what is forbidden
// there: hue must not encode depth. Depth drives brightness, and the hue ramp is
// a narrow warm one — ember at the far end, warm white at the near end — so the
// tunnel reads as one lit material rather than as a rainbow.
//
// Both ends are existing tokens rather than invented values, which is the same
// reason the old ink took brgen's --text instead of picking a grey: a second
// private copy of the palette drifts. The ember is design_tokens.yml
// luxury.light_danger #a7473b and the near tone is luxury.light_bg #f8f5f0, the
// warm paper amber is built on. Full-saturation ember only ever appears at
// INK_ALPHA_MIN over black, so the far end reads as a dark coal, not as a
// warning colour.
// The operator's palette and ring modes live in radio_brgen_modes.js.
// Far rings barely present, near rings solid — the 8%-to-full range the face
// works in, expressed 0..1.
