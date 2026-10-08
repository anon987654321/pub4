import { publishVisual } from "pub4/visual_field"

'use strict'

const DEFAULT_TRACKS = [
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
const OPENING_TRACK_ID = "9EGHwkDix78"

// FFT band edges as a fraction of the spectrum. 2048 bins over ~44.1kHz puts
// bass under ~250Hz, mids to ~2kHz, highs above — the split that makes a kick
// move the ring and a hat shimmer it.
const BAND_BASS = 0.012
const BAND_MID = 0.09

class AudioEngine {
  constructor({ iframe, trackDisplay, tracks = DEFAULT_TRACKS }) {
    this.iframe = iframe
    this.trackDisplay = trackDisplay
    this.tracks = tracks.length ? tracks : DEFAULT_TRACKS
    this.isPlaying = false
    const opener = this.tracks.findIndex((track) => track.id === OPENING_TRACK_ID)
    this.currentTrack = opener >= 0 ? opener : Math.floor(Math.random() * this.tracks.length)
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
      album: "Radio Bergen",
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
    if (this.audio) this.audio.pause()
    const embedUrl = `https://www.youtube.com/embed/${track.id}?autoplay=1&controls=0&disablekb=1&fs=0&iv_load_policy=3&modestbranding=1&playsinline=1&rel=0&showinfo=0&origin=${encodeURIComponent(window.location.origin)}`
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
    this.#publishTrack()
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
    this.#publishTrack()
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

  updateTrackDisplay() {
    if (!this.trackDisplay) return
    const track = this.tracks[this.currentTrack]
    if (!track) return
    this.trackDisplay.textContent = `${track.artist} - ${track.title}`
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
// The original Radio Bergen palette: cool blue/teal on black.
const INK_FAR = { r: 4 / 255, g: 27 / 255, b: 37 / 255 }
const INK_NEAR = { r: 78 / 255, g: 205 / 255, b: 196 / 255 }
// Far rings barely present, near rings solid — the 8%-to-full range the face
// works in, expressed 0..1.
const INK_ALPHA_MIN = 0.08
const INK_ALPHA_MAX = 0.78

// One pixel per particle, so the buffer is the grid. Capping it means a phone
// and a television draw the same tunnel and the television simply upscales it —
// uncapped, the buffer grew with the display while the ring count stayed fixed,
// which both thinned the image and cost 4x more to draw. Mirrors the face's
// FACE_BUFFER_MAX_W/H.
const BUFFER_MAX_W = 960
const BUFFER_MAX_H = 640

// Phosphor decay: dim the previous frame rather than clearing it, so particles
// leave a trail as they approach. The trail stays in the same pass; no second
// glow layer is introduced.
// Postures. Named weight sets the engine eases toward, never snaps to — the
// easing is the whole effect, because a creature that changed shape on a frame
// boundary would read as a scene cut. Weights compose, so `dormant` still
// swallows and still leans; it does everything more slowly and more slackly.
const POSTURES = {
  awake: { peristalsis: 0.55, lean: 0.30, twist: 0.0016, sag: 0.0, spread: 1.0, exposure: 1.0, speedScale: 1.0 },
  dormant: { peristalsis: 0.18, lean: 0.14, twist: 0.0006, sag: 1.0, spread: 1.28, exposure: 0.55, speedScale: 0.22 },
  // Held for a beat after an onset — the tunnel flinches open, then settles.
  startled: { peristalsis: 0.85, lean: 0.44, twist: 0.0034, sag: 0.0, spread: 1.06, exposure: 1.18, speedScale: 1.5 }
}

// How long the audio has to stay silent before the tunnel goes dormant.
// getAudioData returns a flat zero when nothing is playing, so this is really
// "nobody has started the radio", which is the state a first-time visitor sits
// in. Dormancy is most of what makes a thing read as alive: something that
// never rests is a motor.
const DORMANT_AFTER_MS = 30000
const STARTLE_MS = 900

const VERT = `
precision highp float;
attribute float aAngle;
attribute float aRingT;
attribute float aSeed;
uniform float uTime;
uniform float uZ;
uniform float uFov;
uniform float uRadius;
uniform vec2 uResolution;
uniform vec2 uCenter;
uniform float uBass;
uniform float uMid;
uniform float uHigh;
uniform float uBeat;
uniform float uBreath;
// Posture. Each weight is eased on the CPU toward a named target, and they
// compose rather than exclude — a dormant tunnel still swallows, just slower.
// A creature reads as alive through involuntary movement, not through a
// repertoire of poses, so these are all things the tunnel does to itself.
uniform float uPeristalsis;
uniform float uLean;
uniform float uTwist;
uniform float uSag;
uniform float uSpread;
varying float vNear;
varying float vSeed;

// The lean. Two incommensurable sine pairs, so the curve never repeats on any
// interval a viewer can learn. The far rings displace most, which bends the
// tube into a spine — and roughly twice a minute the far end swings round into
// line with the near end and the tunnel is looking down its own length at you.
// That moment is not scheduled; it falls out of the drift, which is why it
// lands as being watched rather than as an animation.
vec2 leanAt(float t, float time) {
  float a = t * 3.1 + time * 0.11;
  float b = t * 2.3 - time * 0.07;
  return vec2(sin(a) + 0.5 * sin(b * 1.7), cos(b) + 0.5 * cos(a * 1.3));
}

void main() {
  // Ring depth scrolls in the shader. The CPU used to walk 6,000 particles a
  // frame adding a delta and re-sorting the rows; the same motion is one
  // subtraction here, and nothing needs sorting because nothing is drawn
  // back-to-front any more.
  float span = uFov * 2.0;
  float z = mod(aRingT * span + uZ, span) - uFov;
  float near = clamp(1.0 - (z + uFov) / span, 0.0, 1.0);

  // Bass swells the ring, highs shimmer it per-particle. This is the audio
  // reactivity that was previously impossible: a YouTube iframe is cross-origin
  // so no AnalyserNode could see it, and the numbers driving this were a sine
  // wave. They are now real FFT bands.
  float shimmer = sin(aSeed * 6.2831 + uTime * 7.0) * uHigh * 0.05;
  float beatKick = uBeat * (0.16 - 0.06 * near);
  float radius = uRadius * (1.0 + uBass * 0.22 + uMid * 0.08 + beatKick + shimmer) * uBreath;

  // Peristalsis — a travelling constriction, keyed to z rather than to ring
  // index so the wave moves through the tube instead of riding along with it.
  // This is the one that turns a corridor into a throat.
  radius *= 1.0 + uPeristalsis * 0.28 * sin((z / uFov) * 9.4248 - uTime * 2.2);

  // Dormancy: the ring loosens and each particle drifts out by its own seed,
  // so a sleeping tunnel goes slack rather than merely slow.
  radius *= uSpread * (1.0 + uSag * aSeed * 0.22);

  float ang = aAngle + uTime + z * uTwist;

  // Distortion is a real geometric warp: three slow, incommensurate waves pinch
  // each ring differently along depth, restoring the crooked hand-drawn tunnel.
  float warp = sin(ang * 3.0 + z * 0.020 - uTime * 1.65) *
    (0.08 + uMid * 0.08) *
    (0.30 + 0.70 * near);
  float skew = cos(ang * 2.0 - z * 0.013 + uTime * 0.72) *
    (0.035 + uBeat * 0.045);
  vec2 p = vec2(cos(ang), sin(ang)) * radius;
  p.x *= 1.0 + warp;
  p.y *= 1.0 - warp * 0.58;
  p += vec2(
    sin(z * 0.018 - uTime * 0.62) * uRadius * 0.035 * uLean,
    cos(z * 0.015 + uTime * 0.47) * uRadius * 0.028 * uLean
  );
  p += vec2(skew, -skew * 0.7) * radius;

  p += leanAt(aRingT, uTime) * uLean * uRadius * (0.25 + 0.75 * (1.0 - near));
  // Gravity on the far end only — the near rings hold, so the tube sags away
  // from the viewer the way a held rope does.
  p.y += uSag * (1.0 - near) * uRadius * 0.30;

  // Guard the FOV singularity at z = -uFov so scale never blows up or NaNs.
  float denom = max(0.5, uFov + z);
  float scale = uFov / denom;
  vec2 screen = p * scale + uCenter;

  gl_Position = vec4(
    (screen.x / uResolution.x) * 2.0 - 1.0,
    1.0 - (screen.y / uResolution.y) * 2.0,
    0.0,
    1.0
  );
  // One point is one pixel — the same law the MASTER face obeys
  // (FACE_POINT_IS_ONE_PIXEL). Depth is carried by brightness below, because a
  // pixel has no size to give.
  gl_PointSize = 1.0;

  vNear = near;
  vSeed = aSeed;
}`

const FRAG = `
precision highp float;
uniform vec3 uInkFar;
uniform vec3 uInkNear;
uniform float uAlphaMin;
uniform float uAlphaMax;
uniform float uExposure;
// Blink. -1 when idle; otherwise the position of a lid sweeping through the
// tube in near-space, front to back. It is in the fragment stage because
// that is where alpha already lives, and a blink is a dimming rather than a
// movement -- a creature closing its eye does not change shape.
uniform float uBlink;
// Screen door. topologies.yml names dithering as the channel for uncertainty
// and density as the channel for pressure, and no renderer has ever drawn
// either. 0 keeps the continuous alpha this shader has always used, so the
// two can be compared on one machine before either is preferred.
uniform float uDither;
varying float vNear;
varying float vSeed;
// Ordered 4x4 Bayer by nested 2x2 recursion, matching the matrix
// particle_kernel.bayer4 uses. GLSL ES 1.00 has no integer bit operators, so
// the table lookup that file can write is not available here.
float bayer2(vec2 a) { a = floor(a); return fract(a.x * 0.5 + a.y * a.y * 0.75); }
float bayer4(vec2 a) { return (bayer2(0.5 * a) * 0.25 + bayer2(a)) * 1.06667; }
void main() {
  // No gl_PointCoord shaping: at gl_PointSize 1.0 there is no interior to carve.
  float near = vNear * vNear;
  float alpha = mix(uAlphaMin, uAlphaMax, near) * uExposure;
  if (uBlink >= 0.0) alpha *= 1.0 - 0.92 * (1.0 - smoothstep(0.0, 0.16, abs(near - uBlink)));
  vec3 col = mix(uInkFar, uInkNear, near);
  if (uDither > 0.5) {
    // Depth stops being alpha and becomes ink density: the fragment is drawn
    // whole or discarded, and how often it wins its cell is how far away it
    // is. At gl_PointSize 1.0 the far half of the tube otherwise spends its
    // entire range inside a handful of 8-bit values above black. No size, no
    // second pass, no glow -- this stays inside pixel_perfection.
    if (alpha < bayer4(gl_FragCoord.xy)) discard;
    gl_FragColor = vec4(col, 1.0);
    return;
  }
  gl_FragColor = vec4(col, alpha);
}`

function compile(gl, type, src, label) {
  const s = gl.createShader(type)
  gl.shaderSource(s, src)
  gl.compileShader(s)
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
    const log = gl.getShaderInfoLog(s)
    gl.deleteShader(s)
    throw new Error(`radio_brgen_tunnel: ${label} failed to compile: ${log}`)
  }
  return s
}

function program(gl, vsrc, fsrc, label) {
  const p = gl.createProgram()
  gl.attachShader(p, compile(gl, gl.VERTEX_SHADER, vsrc, `${label} vertex`))
  gl.attachShader(p, compile(gl, gl.FRAGMENT_SHADER, fsrc, `${label} fragment`))
  gl.linkProgram(p)
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
    const log = gl.getProgramInfoLog(p)
    gl.deleteProgram(p)
    throw new Error(`radio_brgen_tunnel: ${label} failed to link: ${log}`)
  }
  return p
}

class VisualEngine {
  constructor(canvas) {
    this.canvas = canvas
    this.particles = []
    this.centers = []
    this.mouse = { x: 0, y: 0, down: false, active: false }
    this.touch = { x: 0, y: 0, active: false }
    this.tilt = { x: 0, y: 0 }
    this.time = 0
    this.zOffset = 0
    this.colorInvertValue = 0
    this.audioBoost = 0
    this.breath = 1
    this.heart = 0
    this.posture = { ...POSTURES.awake }
    this.postureName = "awake"
    this._lastLoudAt = performance.now()
    this._startledUntil = 0
    this._bassEnv = 0
    this.lastBass = 0
    this.blink = -1
    // Off until the two have been compared on one machine.
    this.dither = false
    this._blinkAt = performance.now() + 21000
    this.isMobile = window.innerWidth < 768 || "ontouchstart" in window
    // Classic c7c8effcd / Radio Bergen tunnel: fov 250, speed 0.75, dense rings.
    this.config = {
      fov: 250,
      speed: 0.75,
      particleCountPerRow: this.isMobile ? 32 : 48,
      zStep: this.isMobile ? 7 : 5
    }
    // One-pixel line drawing, no antialiasing. The back buffer is disposable:
    // the tunnel clears each frame, so preserving it only adds memory traffic.
    const opts = { alpha: false, antialias: false, depth: false, preserveDrawingBuffer: false }
    this.gl = canvas.getContext("webgl", opts) || canvas.getContext("experimental-webgl", opts)
    if (this.gl) {
      try {
        this.#initGL()
      } catch (err) {
        console.warn("radio_brgen_tunnel: WebGL init failed, falling back to 2D", err)
        this.gl = null
      }
    }
    if (!this.gl) this.#initFallback()
    this.resize()
  }

  #initGL() {
    const gl = this.gl
    this.prog = program(gl, VERT, FRAG, "tunnel")
    this.attr = {
      angle: gl.getAttribLocation(this.prog, "aAngle"),
      ringT: gl.getAttribLocation(this.prog, "aRingT"),
      seed: gl.getAttribLocation(this.prog, "aSeed")
    }
    this.uni = {}
    for (const n of ["uTime", "uZ", "uFov", "uRadius", "uResolution", "uCenter",
      "uBass", "uMid", "uHigh", "uBreath", "uInkFar", "uInkNear",
      "uAlphaMin", "uAlphaMax", "uExposure",
      "uPeristalsis", "uLean", "uTwist", "uSag", "uSpread", "uBlink", "uDither"]) {
      this.uni[n] = gl.getUniformLocation(this.prog, n)
    }
    this.angleBuf = gl.createBuffer()
    this.ringBuf = gl.createBuffer()
    this.seedBuf = gl.createBuffer()
    this.lineAngleBuf = gl.createBuffer()
    this.lineRingBuf = gl.createBuffer()
    this.lineSeedBuf = gl.createBuffer()
    gl.disable(gl.DEPTH_TEST)
    gl.enable(gl.BLEND)
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    gl.clearColor(0, 0, 0, 1)
  }

  #initFallback() {
    this.ctx = this.canvas.getContext("2d")
  }

  resize() {
    // The canvas is position:fixed inset:0, so its box is the layout viewport,
    // which window.innerWidth/Height is not: on a phone they differ by the
    // browser chrome, and on a desktop with a classic scrollbar by its width.
    // Sizing the buffer from the window stretched the tunnel by that delta and
    // skewed the pointer mapping below, which divides by these same numbers.
    const rect = this.canvas.getBoundingClientRect()
    const vw = Math.max(1, Math.round(rect.width) || window.innerWidth)
    const vh = Math.max(1, Math.round(rect.height) || window.innerHeight)
    // Cap both axes by one shared factor so the buffer's aspect keeps matching
    // the stretched element's; clamping them independently would squash it.
    const cap = Math.min(1, BUFFER_MAX_W / vw, BUFFER_MAX_H / vh)
    this.w = Math.max(1, Math.floor(vw * cap))
    this.h = Math.max(1, Math.floor(vh * cap))
    this.canvas.width = this.w
    this.canvas.height = this.h
    this.canvas.style.imageRendering = "pixelated"
    this.centerX = this.w / 2
    this.centerY = this.h / 2
    this.centerNow = { x: this.centerX, y: this.centerY }
    this.viewW = vw
    this.viewH = vh
    if (this.gl) this.gl.viewport(0, 0, this.w, this.h)
    else if (this.ctx) { this.ctx.fillStyle = "#000"; this.ctx.fillRect(0, 0, this.w, this.h) }
    this.initParticles()
  }

  initParticles() {
    const { fov, zStep, particleCountPerRow } = this.config
    const rows = Math.max(1, Math.round((fov * 2) / zStep))
    const count = rows * particleCountPerRow
    const angle = new Float32Array(count)
    const ringT = new Float32Array(count)
    const seed = new Float32Array(count)
    const angleStep = (Math.PI * 2) / particleCountPerRow
    let k = 0
    for (let i = 0; i < rows; i++) {
      for (let j = 0; j < particleCountPerRow; j++) {
        angle[k] = j * angleStep
        ringT[k] = i / rows
        // Deterministic per-particle offset. Math.random here would reshuffle
        // the shimmer on every resize, which reads as the tunnel flinching.
        seed[k] = ((i * 73 + j * 151) % 997) / 997
        k += 1
      }
    }

    // The original tunnel was a connected mesh, not a cloud of dots. Keep that
    // character, but put the entire edge list in three static GPU buffers:
    // ring loops + longitudinal seams become one GL_LINES draw instead of
    // thousands of CPU line/pixel operations every frame.
    const edgeCount = particleCountPerRow * (rows + rows - 1)
    const lineVertexCount = edgeCount * 2
    const lineAngle = new Float32Array(lineVertexCount)
    const lineRingT = new Float32Array(lineVertexCount)
    const lineSeed = new Float32Array(lineVertexCount)
    let edge = 0
    const pushVertex = (index, out) => {
      lineAngle[out] = angle[index]
      lineRingT[out] = ringT[index]
      lineSeed[out] = seed[index]
    }
    for (let i = 0; i < rows; i++) {
      for (let j = 0; j < particleCountPerRow; j++) {
        const a = i * particleCountPerRow + j
        const b = i * particleCountPerRow + ((j + 1) % particleCountPerRow)
        pushVertex(a, edge * 2)
        pushVertex(b, edge * 2 + 1)
        edge += 1
        if (i < rows - 1) {
          const c = (i + 1) * particleCountPerRow + j
          pushVertex(a, edge * 2)
          pushVertex(c, edge * 2 + 1)
          edge += 1
        }
      }
    }

    this.pointCount = count
    this.lineVertexCount = lineVertexCount
    this.rows = rows
    this.particles = []
    this.centers = []
    if (!this.gl) {
      this.cpuAngle = angle
      this.cpuRingT = ringT
      this.cpuSeed = seed
      return
    }
    const gl = this.gl
    gl.bindBuffer(gl.ARRAY_BUFFER, this.angleBuf)
    gl.bufferData(gl.ARRAY_BUFFER, angle, gl.STATIC_DRAW)
    gl.bindBuffer(gl.ARRAY_BUFFER, this.ringBuf)
    gl.bufferData(gl.ARRAY_BUFFER, ringT, gl.STATIC_DRAW)
    gl.bindBuffer(gl.ARRAY_BUFFER, this.seedBuf)
    gl.bufferData(gl.ARRAY_BUFFER, seed, gl.STATIC_DRAW)
    gl.bindBuffer(gl.ARRAY_BUFFER, this.lineAngleBuf)
    gl.bufferData(gl.ARRAY_BUFFER, lineAngle, gl.STATIC_DRAW)
    gl.bindBuffer(gl.ARRAY_BUFFER, this.lineRingBuf)
    gl.bufferData(gl.ARRAY_BUFFER, lineRingT, gl.STATIC_DRAW)
    gl.bindBuffer(gl.ARRAY_BUFFER, this.lineSeedBuf)
    gl.bufferData(gl.ARRAY_BUFFER, lineSeed, gl.STATIC_DRAW)
  }

  update(audioData) {
    this.time += 0.005
    const bass = Math.max(0, Math.min(1, audioData?.bass || 0))
    const mid = Math.max(0, Math.min(1, audioData?.mid || 0))
    const high = Math.max(0, Math.min(1, audioData?.high || 0))
    const average = Math.max(0, Math.min(1, audioData?.average || 0))
    this.bass = bass
    this.mid = mid
    this.high = high
    this.audioBoost = average * 0.5

    // Breathing: a slow swell independent of the music, so the tunnel is alive
    // even in a quiet passage. ~9s period.
    const now = performance.now()
    this.breath = 1 + 0.05 * Math.sin(now * 0.0007)

    // Blink: a lid sweeping the length of the tube in about 380ms, then a long
    // wait. The interval is deliberately not a round number and carries a wide
    // random spread, because a blink on a rhythm is a strobe -- the eye learns
    // any period under a minute and stops reading it as involuntary. Sleeping
    // things blink less, so dormancy stretches the wait rather than stopping it.
    if (this.blink >= 0) {
      this.blink += 0.055
      if (this.blink > 1.16) {
        this.blink = -1
        this._blinkAt = now + 23700 + Math.random() * 41300 * (2 - this.posture.speedScale)
      }
    } else if (now >= this._blinkAt) {
      this.blink = 0
    }

    // Onset detection against a decaying envelope. A rising bass edge is the
    // startle; the envelope means a sustained loud passage does not keep
    // retriggering it, which is the difference between a flinch and a shudder.
    this._bassEnv = Math.max(bass, this._bassEnv * 0.94)
    const onset = bass - this._bassEnv > -0.001 && bass > 0.12 && bass - this.lastBass > 0.10
    this.lastBass = bass
    if (average > 0.02) this._lastLoudAt = now
    if (onset) {
      this._startledUntil = now + STARTLE_MS
      // Lub-dub, not a motor. The second thump is the smaller one.
      this.heart = 1
    }
    this.heart *= 0.90

    const quietFor = now - this._lastLoudAt
    this.postureName = now < this._startledUntil
      ? "startled"
      : (quietFor > DORMANT_AFTER_MS ? "dormant" : "awake")
    const target = POSTURES[this.postureName]
    // Waking is faster than falling asleep. Something that dozes off as sharply
    // as it wakes up reads as a switch rather than as a body.
    const ease = this.postureName === "dormant" ? 0.006 : 0.045
    for (const k of Object.keys(target)) {
      this.posture[k] += (target[k] - this.posture[k]) * ease
    }

    // Classic: hold = reverse (fly out), release = fly forward into the tunnel.
    const isPressed = this.mouse.down
    const beat = 1 + this.heart * 0.9
    const speed = this.config.speed * this.posture.speedScale * beat * (1 + this.bass * 0.18)
    this.zOffset += isPressed ? speed : -speed

    const interactionX = this.touch.active ? this.touch.x : this.mouse.x
    const interactionY = this.touch.active ? this.touch.y : this.mouse.y
    const isInteracting = (this.touch.active || this.mouse.active) && this.mouse.down
    const tiltX = this.tilt.x * this.w
    const tiltY = this.tilt.y * this.h
    const c = this.centerNow
    if (isInteracting) {
      // Pointer coordinates arrive in viewport space; the buffer is capped, so
      // they must be scaled into it or the tunnel leans the wrong distance.
      const sx = this.w / (this.viewW || this.w)
      const sy = this.h / (this.viewH || this.h)
      c.x += (this.centerX + (this.centerX - interactionX * sx) * 0.35 - c.x) * 0.08
      c.y += (this.centerY + (this.centerY - interactionY * sy) * 0.35 - c.y) * 0.08
    } else {
      c.x += (this.centerX + tiltX - c.x) * 0.015
      c.y += (this.centerY + tiltY - c.y) * 0.015
    }

    if (isPressed) this.colorInvertValue = Math.min(255, this.colorInvertValue + 5)
    else this.colorInvertValue = Math.max(0, this.colorInvertValue - 5)
  }

  render() {
    if (this.gl) return this.#renderGL()
    return this.#renderFallback()
  }

  #renderGL() {
    const gl = this.gl
    // Clear like the original reference. This keeps the buffer disposable and
    // lets the browser avoid a costly preserved-backbuffer path.\n\n    gl.useProgram(this.prog)
    const bind = (buf, loc) => {
      if (loc < 0) return
      gl.bindBuffer(gl.ARRAY_BUFFER, buf)
      gl.enableVertexAttribArray(loc)
      gl.vertexAttribPointer(loc, 1, gl.FLOAT, false, 0, 0)
    }
    bind(this.angleBuf, this.attr.angle)
    bind(this.ringBuf, this.attr.ringT)
    bind(this.seedBuf, this.attr.seed)

    const u = this.uni
    gl.uniform1f(u.uTime, this.time)
    gl.uniform1f(u.uZ, this.zOffset)
    gl.uniform1f(u.uFov, this.config.fov)
    // Ring radius scales with the buffer DIAGONAL, not its smaller side.
    //
    // min(w, h) sized the tunnel to whichever axis was shorter, which on any
    // landscape window is the height -- so the rings were scaled to fit
    // vertically and could never reach the sides. At 960x540 that is a ring
    // diameter of 25% of the width against 44% of the height, and the tunnel
    // sat in the middle of the frame with the window showing past it. The
    // comment here used to claim it "fills the frame identically at every
    // size"; it filled PROPORTIONALLY at every size, which is a different
    // thing and is why the visualiser covered about two thirds of the window.
    //
    // The diagonal is the dimension that guarantees corner coverage whatever
    // the aspect: half of it is the distance from centre to corner. 0.19 puts
    // the near rings just past that, so the tunnel bleeds off every edge
    // rather than ending inside the frame, and it stays right in portrait,
    // where sizing by the larger side alone would not.
    gl.uniform1f(u.uRadius, Math.hypot(this.w, this.h) * 0.19)
    gl.uniform2f(u.uResolution, this.w, this.h)
    gl.uniform2f(u.uCenter, this.centerNow.x, this.centerNow.y)
    gl.uniform1f(u.uBass, this.bass || 0)
    gl.uniform1f(u.uMid, this.mid || 0)
    gl.uniform1f(u.uHigh, this.high || 0)
    gl.uniform1f(u.uBeat, this.beat || 0)
    gl.uniform1f(u.uBreath, this.breath || 1)
    const post = this.posture
    gl.uniform1f(u.uPeristalsis, post.peristalsis)
    gl.uniform1f(u.uLean, post.lean)
    gl.uniform1f(u.uTwist, post.twist)
    gl.uniform1f(u.uSag, post.sag)
    gl.uniform1f(u.uSpread, post.spread)
    gl.uniform1f(u.uBlink, this.blink)
    gl.uniform1f(u.uDither, this.dither ? 1 : 0)
    // Press inverts toward warm white rather than flipping the buffer: the old
    // softInvert walked every byte of the image on the CPU each pressed frame.
    const inv = this.colorInvertValue / 255
    gl.uniform3f(u.uInkFar, INK_FAR.r + inv * 0.4, INK_FAR.g + inv * 0.5, INK_FAR.b + inv * 0.5)
    gl.uniform3f(u.uInkNear, INK_NEAR.r, INK_NEAR.g, INK_NEAR.b)
    gl.uniform1f(u.uAlphaMin, INK_ALPHA_MIN)
    gl.uniform1f(u.uAlphaMax, INK_ALPHA_MAX)
    gl.uniform1f(u.uExposure, (0.85 + (this.audioBoost || 0) * 0.3) * post.exposure)

    if (this.lineVertexCount > 0) {
      const bindLine = (buf, loc) => {
        if (loc < 0) return
        gl.bindBuffer(gl.ARRAY_BUFFER, buf)
        gl.enableVertexAttribArray(loc)
        gl.vertexAttribPointer(loc, 1, gl.FLOAT, false, 0, 0)
      }
      bindLine(this.lineAngleBuf, this.attr.angle)
      bindLine(this.lineRingBuf, this.attr.ringT)
      bindLine(this.lineSeedBuf, this.attr.seed)
      // The shader already calculates the same distorted 3D position for both
      // endpoints. GL_LINES reconnects the historic radial grid without
      // touching the CPU per frame.
      gl.drawArrays(gl.LINES, 0, this.lineVertexCount)
    }
  }

  #renderFallback() {
    const ctx = this.ctx
    if (!ctx) return

    // Fallback keeps the same connected tunnel using native paths. It is
    // intentionally lower density than WebGL, so an older browser degrades
    // gracefully instead of recreating the original pixel-grind.
    ctx.fillStyle = "#000"
    ctx.fillRect(0, 0, this.w, this.h)

    const { fov, particleCountPerRow, zStep } = this.config
    const rows = Math.max(1, Math.round((fov * 2) / zStep))
    const span = fov * 2
    const radius = Math.hypot(this.w, this.h) * 0.19 *
      (1 + (this.bass || 0) * 0.18) * (this.breath || 1)
    const center = this.centerNow
    const point = (ring, index) => {
      const z = ((((ring / rows) * span + this.zOffset) % span) + span) % span - fov
      const ang = (index / particleCountPerRow) * Math.PI * 2 + this.time + z * 0.0016
      let warp = 1 +
        Math.sin(ang * 3 + z * 0.02 - this.time * 1.65) *
        (0.08 + (this.mid || 0) * 0.08) *
        (0.30 + 0.70 * Math.min(1, Math.max(0, 1 - (z + fov) / span)))
      let skew = Math.cos(ang * 2 - z * 0.013 + this.time * 0.72) *
        (0.035 + (this.beat || 0) * 0.045)
      const r = radius * warp
      const scale = fov / Math.max(0.5, fov + z)
      return {
        x: Math.cos(ang) * r * scale + center.x + skew * radius * scale,
        y: Math.sin(ang) * r * scale + center.y - skew * radius * scale * 0.7,
        z
      }
    }

    ctx.lineWidth = 1
    ctx.globalCompositeOperation = "source-over"

    for (let ring = 0; ring < rows; ring++) {
      const first = point(ring, 0)
      const near = Math.min(1, Math.max(0, 1 - (first.z + fov) / span))
      const alpha = INK_ALPHA_MIN + (INK_ALPHA_MAX - INK_ALPHA_MIN) * near * near
      const r = Math.round((INK_FAR.r + (INK_NEAR.r - INK_FAR.r) * near) * 255)
      const g = Math.round((INK_FAR.g + (INK_NEAR.g - INK_FAR.g) * near) * 255)
      const b = Math.round((INK_FAR.b + (INK_NEAR.b - INK_FAR.b) * near) * 255)
      ctx.globalAlpha = alpha
      ctx.strokeStyle = `rgb(${r} ${g} ${b})`
      ctx.beginPath()
      ctx.moveTo(first.x, first.y)
      for (let j = 1; j <= particleCountPerRow; j++) {
        const p = point(ring, j % particleCountPerRow)
        ctx.lineTo(p.x, p.y)
      }
      ctx.stroke()
    }

    // Only every fourth seam in the fallback: enough to preserve the tunnel
    // lattice without turning an old CPU renderer into the same bottleneck.
    for (let ring = 0; ring < rows - 1; ring++) {
      for (let j = 0; j < particleCountPerRow; j += 4) {
        const a = point(ring, j)
        const b = point(ring + 1, j)
        const near = Math.min(1, Math.max(0, 1 - (a.z + fov) / span))
        const alpha = INK_ALPHA_MIN + (INK_ALPHA_MAX - INK_ALPHA_MIN) * near * near
        ctx.globalAlpha = alpha * 0.72
        ctx.strokeStyle = `rgb(${Math.round((INK_FAR.r + (INK_NEAR.r - INK_FAR.r) * near) * 255)} ${Math.round((INK_FAR.g + (INK_NEAR.g - INK_FAR.g) * near) * 255)} ${Math.round((INK_FAR.b + (INK_NEAR.b - INK_FAR.b) * near) * 255)})`
        ctx.beginPath()
        ctx.moveTo(a.x, a.y)
        ctx.lineTo(b.x, b.y)
        ctx.stroke()
      }
    }
    ctx.globalAlpha = 1
  }

  setTouch(x, y, active) {
    this.touch.x = Math.max(0, Math.min(x, this.viewW || this.w))
    this.touch.y = Math.max(0, Math.min(y, this.viewH || this.h))
    this.touch.active = active
  }

  setMouse(x, y, down, active) {
    this.mouse.x = Math.max(0, Math.min(x, this.viewW || this.w))
    this.mouse.y = Math.max(0, Math.min(y, this.viewH || this.h))
    this.mouse.down = down
    this.mouse.active = active
  }

  setPerformanceMode(value) {
    this.isMobile = value
    this.config.particleCountPerRow = value ? 32 : 48
    this.config.zStep = value ? 7 : 5
    this.initParticles()
  }
}

export class RadioBrgen {
  constructor(options = {}) {
    this.canvas = options.canvas
    this.overlay = options.overlay
    this.onStart = options.onStart
    this.isStarted = false
    this.isMobile = window.innerWidth < 768 || "ontouchstart" in window
    this._boundHandlers = []
    this.audioEngine = new AudioEngine({
      iframe: options.youtubePlayer,
      trackDisplay: options.trackDisplay,
      tracks: options.tracks
    })
    this.visualEngine = new VisualEngine(this.canvas)

    if (options.heading && options.headingText) {
      options.heading.textContent = options.headingText
    }

    this.setupEventListeners()
    this.startAnimation()
  }

  start() {
    if (this.isStarted) return
    this.isStarted = true
    this.audioEngine.setUserInteracted()
    this.audioEngine.start()
    this._bindTilt?.()
    this.audioEngine.publishTrack?.()
    if (this.overlay) this.overlay.hidden = true
    this.onStart?.()
  }

  setupEventListeners() {
    const startExperience = () => this.start()

    const bindTilt = async () => {
      if (window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) return
      const Ctor = window.DeviceOrientationEvent
      if (!Ctor) return
      if (typeof Ctor.requestPermission === "function") {
        try {
          const permission = await Ctor.requestPermission()
          if (permission !== "granted") return
        } catch {
          return
        }
      }
      this._tiltHandler = (event) => {
        if (event.gamma == null) return
        const gamma = Math.max(-20, Math.min(20, event.gamma || 0))
        const beta = Math.max(-20, Math.min(20, (event.beta || 0) - 45))
        this.visualEngine.tilt.x = gamma / 20 * 0.08
        this.visualEngine.tilt.y = beta / 20 * 0.08
      }
      window.addEventListener("deviceorientation", this._tiltHandler, { passive: true })
    }

    const onOverlayClick = () => startExperience()
    const onOverlayKey = (e) => {
      if (["Enter", "Space"].includes(e.code)) {
        e.preventDefault()
        startExperience()
      }
    }

    this._bindTilt = bindTilt
    if (this.overlay) {
      this.overlay.addEventListener("click", onOverlayClick)
      this.overlay.addEventListener("keydown", onOverlayKey)
      this._boundHandlers.push(["overlay", "click", onOverlayClick], ["overlay", "keydown", onOverlayKey])
    }

    if (this.isMobile || "ontouchstart" in window) {
      const onTouchStartOverlay = (e) => { e.preventDefault(); startExperience() }
      if (this.overlay) {
        this.overlay.addEventListener("touchstart", onTouchStartOverlay, { passive: false })
        this._boundHandlers.push(["overlay", "touchstart", onTouchStartOverlay])
      }
    }

    const onMouseMove = (e) => {
      if (!this.isStarted) return
      this.visualEngine.setMouse(e.clientX, e.clientY, this.visualEngine.mouse.down, true)
    }
    const onMouseDown = (e) => {
      if (!this.isStarted) return
      this.visualEngine.setMouse(e.clientX, e.clientY, true, true)
    }
    const onMouseUp = (e) => {
      if (!this.isStarted) return
      this.visualEngine.setMouse(e.clientX, e.clientY, false, true)
    }
    const onKeyDown = (e) => {
      if (!this.isStarted) return
      if (e.code === "Space") { e.preventDefault(); this.audioEngine.nextTrack() }
    }
    const onResize = () => {
      clearTimeout(this._resizeTimer)
      this._resizeTimer = setTimeout(() => {
        this.visualEngine.resize()

      }, 250)
    }

    document.addEventListener("mousemove", onMouseMove)
    document.addEventListener("mousedown", onMouseDown)
    document.addEventListener("mouseup", onMouseUp)
    document.addEventListener("keydown", onKeyDown)
    window.addEventListener("resize", onResize)
    this._boundHandlers.push(
      ["document", "mousemove", onMouseMove],
      ["document", "mousedown", onMouseDown],
      ["document", "mouseup", onMouseUp],
      ["document", "keydown", onKeyDown],
      ["window", "resize", onResize]
    )

    if (this.isMobile || "ontouchstart" in window) {
      const onTouchStart = (e) => {
        if (!this.isStarted) return
        e.preventDefault()
        const touch = e.touches[0]
        this.visualEngine.setTouch(touch.clientX, touch.clientY, true)
        this.visualEngine.setMouse(touch.clientX, touch.clientY, true, false)
      }
      const onTouchMove = (e) => {
        if (!this.isStarted) return
        e.preventDefault()
        const touch = e.touches[0]
        this.visualEngine.setTouch(touch.clientX, touch.clientY, true)
      }
      const onTouchEnd = (e) => {
        if (!this.isStarted) return
        e.preventDefault()
        this.visualEngine.setTouch(0, 0, false)
        this.visualEngine.setMouse(0, 0, false, false)
      }
      document.addEventListener("touchstart", onTouchStart, { passive: false })
      document.addEventListener("touchmove", onTouchMove, { passive: false })
      document.addEventListener("touchend", onTouchEnd, { passive: false })
      this._boundHandlers.push(
        ["document", "touchstart", onTouchStart],
        ["document", "touchmove", onTouchMove],
        ["document", "touchend", onTouchEnd]
      )
    }
  }

  startAnimation() {
    // A single throw inside update()/render() previously killed the entire
    // animation forever -- requestAnimationFrame is never rescheduled once
    // an exception unwinds past this closure, and canvas particle math is
    // exactly the kind of code that hits a rare NaN/divide-by-zero after a
    // few seconds of continuous audio-driven motion. Skip the bad frame,
    // keep the loop alive, so a transient glitch reads as a stutter, not
    // a dead animation.
    const loop = () => {
      try {
        const audioData = this.audioEngine.getAudioData()
        this.visualEngine.update(audioData)
        const visualNow = performance.now()
        if (!this._lastVisualSignalAt || visualNow - this._lastVisualSignalAt >= 50) {
          this._lastVisualSignalAt = visualNow
          publishVisual("radio:audio", {
            topology: "tunnel",
            mode: "radio:tunnel",
            activity: audioData.average,
            arousal: audioData.average,
            confidence: 0.92,
            bass: audioData.bass,
            mid: audioData.mid,
            high: audioData.high,
            beat: audioData.beat
          })
        }
        this.visualEngine.render()
      } catch (error) {
        if (typeof console !== "undefined" && console.warn) {
          console.warn("radio_brgen_tunnel: animation frame failed, continuing", error)
        }
      }
      this._raf = requestAnimationFrame(loop)
    }
    loop()
  }

  destroy() {
    this._destroyed = true
    cancelAnimationFrame(this._raf)
    this.audioEngine.stop()
    if (this._tiltHandler) window.removeEventListener("deviceorientation", this._tiltHandler)
    this._boundHandlers.forEach(([target, event, handler]) => {
      const el = target === "overlay" ? this.overlay : target === "window" ? window : document
      if (el) el.removeEventListener(event, handler)
    })
  }
}

export { VisualEngine }
