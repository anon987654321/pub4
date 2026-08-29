'use strict'

const DEFAULT_TRACKS = [
  { title: "Microphone Master", id: "9EGHwkDix78", artist: "J Dilla" },
  { title: "In Space", id: "vO2nWXCVt6o", artist: "J Dilla" },
  { title: "Timeless", id: "dbbfo9_7D8g", artist: "J Dilla" },
  { title: "Due Time", id: "WC09qDzU9y4", artist: "AFTA-1" },
  { title: "Massage Situation", id: "6oUx6wGCekM", artist: "Flying Lotus" },
  { title: "Eye", id: "ScVz2mntmCE", artist: "Madlib" },
  { title: "Players", id: "KsULjOCYdnY", artist: "Slum Village" },
  { title: "Exhibit A", id: "H3UIHZshNQ0", artist: "Jay Electronica" },
  { title: "La La (Instrumental)", id: "EYJxxHQ7sX0", artist: "Slum Village" },
  { title: "Get It Together", id: "t6T-Q6HMbEo", artist: "Slum Village" },
  { title: "Fantastic", id: "a3ISYWWYgz8", artist: "Slum Village" },
  { title: "me Yesterday//Corded", id: "8DgAhgmpXNA", artist: "Flying Lotus" },
  { title: "Camel", id: "fU9YRGLPDQ8", artist: "Flying Lotus" },
  { title: "Golden Diva", id: "iu4FVvR2QQs", artist: "Flying Lotus" },
  { title: "Worlds Full of Sadness", id: "MU3nfxsz2XA", artist: "Slum Village" },
  { title: "Sarria's Mind", id: "gFKArkiz8vU", artist: "A. Mochi & Takaaki Itoh" },
  { title: "Rounded", id: "oeaY2h_cKsg", artist: "Samiyam" },
  { title: "Traffic", id: "bH-30pDoQdo", artist: "Chase Swayze" },
  { title: "Underrated", id: "1jjFk2Vp5ok", artist: "Chase Swayze" },
  { title: "BTS Radio 2006", id: "6nWdggkulHk", artist: "Flying Lotus" }
]

// Radio Bergen opens on the same track every session. A station has a signature
// tune; a shuffle has none, and the first thing a visitor heard used to be
// whichever of 24 tracks Math.random landed on. AFTA-1's "Due Time" is the
// opener by operator decision. Rotation is random only after it has played, and
// the lookup is by id so reordering the manifest cannot silently unpin it.
const OPENING_TRACK_ID = "WC09qDzU9y4"

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
    this.startTime = 0
    this.audio = null
    this.analyser = null
    this.bins = null
  }

  get currentIsLocal() {
    return Boolean(this.tracks[this.currentTrack]?.src)
  }

  start() {
    if (!this.userInteracted) return false
    this.loadCurrentTrack()
    this.startTime = performance.now()
    this.updateTrackDisplay()
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
      this.analyser.smoothingTimeConstant = 0.72
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
    if (this.iframe && this.iframe.src) this.iframe.src = ""
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

  nextTrack() {
    this.currentTrack = (this.currentTrack + 1) % this.tracks.length
    this.retryCount = 0
    this.loadCurrentTrack()
    this.updateTrackDisplay()
  }

  getAudioData() {
    if (!this.isPlaying) return { bass: 0, mid: 0, high: 0, average: 0 }

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
      for (let i = 0; i < bassEnd; i++) b += this.bins[i]
      for (let i = bassEnd; i < midEnd; i++) m += this.bins[i]
      for (let i = midEnd; i < len; i++) h += this.bins[i]
      const bass = Math.min(1, (b / bassEnd / 255) * this.bassInfluence)
      const mid = Math.min(1, (m / (midEnd - bassEnd) / 255) * this.midInfluence)
      // Highs are quiet in absolute terms in most mixes, so a flat normalise
      // leaves the shimmer term permanently near zero.
      const high = Math.min(1, (h / (len - midEnd) / 255) * 2.6 * this.highInfluence)
      this.bassLevel = bass
      this.midLevel = mid
      this.highLevel = high
      this.audioLevel = (bass + mid + high) / 3
      return { bass, mid, high, average: this.audioLevel }
    }

    // A YouTube embed cannot be analysed. Rather than invent a spectrum for it,
    // report a low steady level: the tunnel keeps its own breathing and lean,
    // which are autonomous, and simply does not claim to be hearing anything.
    const level = 0.18
    this.bassLevel = level
    this.midLevel = level
    this.highLevel = level * 0.5
    this.audioLevel = level
    return { bass: level, mid: level, high: level * 0.5, average: level }
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
const INK_FAR = { r: 167 / 255, g: 71 / 255, b: 59 / 255 }
const INK_NEAR = { r: 248 / 255, g: 245 / 255, b: 240 / 255 }
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

// Phosphor decay. The previous frame is dimmed rather than cleared, so every
// particle smears warm behind itself as it flies at the camera. This is the
// glow, and it is a trail rather than a halo: an additive second pass over the
// same geometry is what NO_WEBGL_GLOW_PASS forbids, and it is also what made
// MASTER's face read as a lit wireframe.
const TRAIL_DECAY = 0.82

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
  float radius = uRadius * (1.0 + uBass * 0.18 + uMid * 0.06 + shimmer) * uBreath;

  // Peristalsis — a travelling constriction, keyed to z rather than to ring
  // index so the wave moves through the tube instead of riding along with it.
  // This is the one that turns a corridor into a throat.
  radius *= 1.0 + uPeristalsis * 0.28 * sin((z / uFov) * 9.4248 - uTime * 2.2);

  // Dormancy: the ring loosens and each particle drifts out by its own seed,
  // so a sleeping tunnel goes slack rather than merely slow.
  radius *= uSpread * (1.0 + uSag * aSeed * 0.22);

  float ang = aAngle + uTime + z * uTwist;
  vec2 p = vec2(cos(ang), sin(ang)) * radius;

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
varying float vNear;
varying float vSeed;
void main() {
  // No gl_PointCoord shaping: at gl_PointSize 1.0 there is no interior to carve.
  float near = vNear * vNear;
  float alpha = mix(uAlphaMin, uAlphaMax, near) * uExposure;
  if (uBlink >= 0.0) alpha *= 1.0 - 0.92 * (1.0 - smoothstep(0.0, 0.16, abs(near - uBlink)));
  vec3 col = mix(uInkFar, uInkNear, near);
  gl_FragColor = vec4(col, alpha);
}`

const FADE_VERT = `
precision highp float;
attribute vec2 aQuad;
void main() { gl_Position = vec4(aQuad, 0.0, 1.0); }`

const FADE_FRAG = `
precision highp float;
uniform float uFade;
void main() { gl_FragColor = vec4(0.0, 0.0, 0.0, uFade); }`

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
    this._blinkAt = performance.now() + 21000
    this.isMobile = window.innerWidth < 768 || "ontouchstart" in window
    // Classic c7c8effcd / Radio Bergen tunnel: fov 250, speed 0.75, dense rings.
    this.config = {
      fov: 250,
      speed: 0.75,
      particleCountPerRow: this.isMobile ? 32 : 48,
      zStep: this.isMobile ? 6 : 4
    }
    // antialias: false. Nothing here has an edge to smooth, and MSAA resolves a
    // 1px point as partial coverage across up to four pixels — it costs
    // bandwidth to destroy exactly the crispness this renderer exists for.
    const opts = { alpha: false, antialias: false, depth: false, preserveDrawingBuffer: true }
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
    this.fadeProg = program(gl, FADE_VERT, FADE_FRAG, "phosphor fade")
    this.attr = {
      angle: gl.getAttribLocation(this.prog, "aAngle"),
      ringT: gl.getAttribLocation(this.prog, "aRingT"),
      seed: gl.getAttribLocation(this.prog, "aSeed")
    }
    this.uni = {}
    for (const n of ["uTime", "uZ", "uFov", "uRadius", "uResolution", "uCenter",
      "uBass", "uMid", "uHigh", "uBreath", "uInkFar", "uInkNear",
      "uAlphaMin", "uAlphaMax", "uExposure",
      "uPeristalsis", "uLean", "uTwist", "uSag", "uSpread", "uBlink"]) {
      this.uni[n] = gl.getUniformLocation(this.prog, n)
    }
    this.fadeAttr = gl.getAttribLocation(this.fadeProg, "aQuad")
    this.fadeUni = gl.getUniformLocation(this.fadeProg, "uFade")
    this.quadBuf = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, this.quadBuf)
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW)
    this.angleBuf = gl.createBuffer()
    this.ringBuf = gl.createBuffer()
    this.seedBuf = gl.createBuffer()
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
    this.pointCount = count
    // `particles` and `centers` stay as length-bearing stubs: the dat.GUI panel
    // and setPerformanceMode read config, but the old per-frame CPU arrays are
    // gone — position is computed in the vertex shader now.
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
    const speed = this.config.speed * this.posture.speedScale * beat
    this.zOffset += isPressed ? speed : -speed

    const interactionX = this.touch.active ? this.touch.x : this.mouse.x
    const interactionY = this.touch.active ? this.touch.y : this.mouse.y
    const isInteracting = (this.touch.active || this.mouse.active) && this.mouse.down
    const c = this.centerNow
    if (isInteracting) {
      // Pointer coordinates arrive in viewport space; the buffer is capped, so
      // they must be scaled into it or the tunnel leans the wrong distance.
      const sx = this.w / (this.viewW || this.w)
      const sy = this.h / (this.viewH || this.h)
      c.x += (this.centerX + (this.centerX - interactionX * sx) * 0.35 - c.x) * 0.08
      c.y += (this.centerY + (this.centerY - interactionY * sy) * 0.35 - c.y) * 0.08
    } else {
      c.x += (this.centerX - c.x) * 0.015
      c.y += (this.centerY - c.y) * 0.015
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
    // Phosphor: dim the previous frame instead of clearing it. A black quad at
    // alpha (1 - decay) under normal blending is dst * decay — the trail.
    gl.useProgram(this.fadeProg)
    gl.bindBuffer(gl.ARRAY_BUFFER, this.quadBuf)
    gl.enableVertexAttribArray(this.fadeAttr)
    gl.vertexAttribPointer(this.fadeAttr, 2, gl.FLOAT, false, 0, 0)
    gl.uniform1f(this.fadeUni, 1 - TRAIL_DECAY)
    gl.drawArrays(gl.TRIANGLES, 0, 3)

    gl.useProgram(this.prog)
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
    gl.uniform1f(u.uBreath, this.breath || 1)
    const post = this.posture
    gl.uniform1f(u.uPeristalsis, post.peristalsis)
    gl.uniform1f(u.uLean, post.lean)
    gl.uniform1f(u.uTwist, post.twist)
    gl.uniform1f(u.uSag, post.sag)
    gl.uniform1f(u.uSpread, post.spread)
    gl.uniform1f(u.uBlink, this.blink)
    // Press inverts toward warm white rather than flipping the buffer: the old
    // softInvert walked every byte of the image on the CPU each pressed frame.
    const inv = this.colorInvertValue / 255
    gl.uniform3f(u.uInkFar, INK_FAR.r + inv * 0.4, INK_FAR.g + inv * 0.5, INK_FAR.b + inv * 0.5)
    gl.uniform3f(u.uInkNear, INK_NEAR.r, INK_NEAR.g, INK_NEAR.b)
    gl.uniform1f(u.uAlphaMin, INK_ALPHA_MIN)
    gl.uniform1f(u.uAlphaMax, INK_ALPHA_MAX)
    gl.uniform1f(u.uExposure, (0.85 + (this.audioBoost || 0) * 0.3) * post.exposure)

    gl.drawArrays(gl.POINTS, 0, this.pointCount)
  }

  #renderFallback() {
    const ctx = this.ctx
    if (!ctx) return
    ctx.fillStyle = `rgba(0,0,0,${(1 - TRAIL_DECAY).toFixed(3)})`
    ctx.fillRect(0, 0, this.w, this.h)
    const { fov } = this.config
    const span = fov * 2
    const radius = Math.hypot(this.w, this.h) * 0.19 * (1 + (this.bass || 0) * 0.18) * (this.breath || 1)
    const c = this.centerNow
    for (let i = 0; i < this.pointCount; i++) {
      const z = ((this.cpuRingT[i] * span + this.zOffset) % span + span) % span - fov
      const ang = this.cpuAngle[i] + this.time
      const scale = fov / Math.max(0.5, fov + z)
      const x = Math.cos(ang) * radius * scale + c.x
      const y = Math.sin(ang) * radius * scale + c.y
      if (x < 0 || x >= this.w || y < 0 || y >= this.h) continue
      const near = Math.min(1, Math.max(0, 1 - (z + fov) / span)) ** 2
      let a = INK_ALPHA_MIN + (INK_ALPHA_MAX - INK_ALPHA_MIN) * near
      // The same lid as the shader. Without this the 2D path would quietly never
      // blink, and the difference between the two renderers would be a behaviour
      // rather than a resolution.
      if (this.blink >= 0) {
        const d = Math.min(1, Math.abs(near - this.blink) / 0.16)
        a *= 1 - 0.92 * (1 - (d * d * (3 - 2 * d)))
      }
      const r = Math.round((INK_FAR.r + (INK_NEAR.r - INK_FAR.r) * near) * 255)
      const g = Math.round((INK_FAR.g + (INK_NEAR.g - INK_FAR.g) * near) * 255)
      const b = Math.round((INK_FAR.b + (INK_NEAR.b - INK_FAR.b) * near) * 255)
      ctx.fillStyle = `rgba(${r},${g},${b},${a.toFixed(3)})`
      ctx.fillRect(x | 0, y | 0, 1, 1)
    }
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
    this.config.zStep = value ? 6 : 4
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

    this.setupGUI()
    this.setupEventListeners()
    this.startAnimation()
  }

  start() {
    if (this.isStarted) return
    this.isStarted = true
    this.audioEngine.setUserInteracted()
    this.audioEngine.start()
    if (this.overlay) this.overlay.hidden = true
    this.onStart?.()
  }

  setupGUI() {
    // Dev-only: dat.GUI autoPlace is a light panel that collides with the
    // top-left brand on the immersive playlist surface.
    if (typeof window.dat === "undefined") return
    if (!window.location.search.includes("datgui=1")) return
    this.gui = new window.dat.GUI({ autoPlace: true, width: 280 })
    const guiParams = {
      particleCount: this.visualEngine.config.particleCountPerRow,
      bassInfluence: this.audioEngine.bassInfluence,
      midInfluence: this.audioEngine.midInfluence,
      highInfluence: this.audioEngine.highInfluence,
      performanceMode: this.visualEngine.isMobile,
      nextTrack: () => this.audioEngine.nextTrack()
    }
    const visFolder = this.gui.addFolder("Visualization")
    visFolder.add(guiParams, "particleCount", 32, 128, 8).name("Particles per Row").onChange(v => {
      this.visualEngine.config.particleCountPerRow = Math.round(v)
      this.visualEngine.initParticles()
    })
    const audioFolder = this.gui.addFolder("Audio Reactivity")
    audioFolder.add(guiParams, "bassInfluence", 0, 2).name("Bass Influence").onChange(v => { this.audioEngine.bassInfluence = v })
    audioFolder.add(guiParams, "midInfluence", 0, 2).name("Mid Influence").onChange(v => { this.audioEngine.midInfluence = v })
    audioFolder.add(guiParams, "highInfluence", 0, 2).name("High Influence").onChange(v => { this.audioEngine.highInfluence = v })
    audioFolder.add(guiParams, "nextTrack").name("Next Track")
    visFolder.add(guiParams, "performanceMode").name("Low Performance").onChange(v => this.visualEngine.setPerformanceMode(v))
  }

  setupEventListeners() {
    const startExperience = () => this.start()

    const onOverlayClick = () => startExperience()
    const onOverlayKey = (e) => {
      if (["Enter", "Space"].includes(e.code)) {
        e.preventDefault()
        startExperience()
      }
    }

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
      this._resizeTimer = setTimeout(() => this.visualEngine.resize(), 250)
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
    cancelAnimationFrame(this._raf)
    this.audioEngine.stop()
    if (this.gui) this.gui.destroy()
    this._boundHandlers.forEach(([target, event, handler]) => {
      const el = target === "overlay" ? this.overlay : target === "window" ? window : document
      if (el) el.removeEventListener(event, handler)
    })
  }
}
