import { Controller } from "@hotwired/stimulus"

// A listening party's audio. The sync target is the broadcast partial
// (playlist/listening_parties/_sync): its data says which track the host is on,
// where it was at synced-at, and whether it is running. A guest's audio element
// follows it; the host's reports back to ListeningPartiesController#update,
// which broadcasts the next sync element to every guest.
export default class extends Controller {
  static targets = ["audio", "sync", "join", "status"]
  static values = {
    host: Boolean,
    syncUrl: String,
    queue: { type: Array, default: [] },
    refusedLabel: String,
    errorLabel: String
  }

  // A guest further than this from the host's position is moved; closer than
  // this, the jump would be heard more than the drift.
  static TOLERANCE = 3
  static HEARTBEAT_MS = 10000

  connect() {
    if (!this.hasAudioTarget) return
    this.audioTarget.addEventListener("error", this.boundError = () => this.#say(this.errorLabelValue))
    if (this.hostValue) this.#bindHost()
    else if (this.hasJoinTarget) this.joinTarget.hidden = false
  }

  disconnect() {
    clearInterval(this.heartbeat)
    if (this.boundError) this.audioTarget.removeEventListener("error", this.boundError)
  }

  // Each broadcast replaces the sync element, which reconnects this target.
  syncTargetConnected(element) {
    this.#follow(element)
  }

  join() {
    this.joined = true
    if (this.hasJoinTarget) this.joinTarget.hidden = true
    if (this.hasSyncTarget) this.#follow(this.syncTarget)
  }

  #follow(element) {
    const audio = this.audioTarget
    const src = element.dataset.src
    if (this.hostValue) {
      if (src && audio.dataset.src !== src) {
        this.#load(src, Number(element.dataset.position) || 0)
        // The broadcast that follows the host's own track change: keep playing.
        if (this.advancing) this.#play()
      }
      this.advancing = false
      return
    }

    if (!src) {
      audio.pause()
      return
    }

    const playing = element.dataset.playing === "true"
    const elapsed = playing ? Math.max(0, Date.now() / 1000 - Number(element.dataset.syncedAt)) : 0
    const target = (Number(element.dataset.position) || 0) + elapsed
    if (audio.dataset.src !== src) this.#load(src, target)
    else if (Math.abs(audio.currentTime - target) > this.constructor.TOLERANCE) audio.currentTime = target

    if (!this.joined) return
    if (playing) this.#play()
    else audio.pause()
  }

  #load(src, position) {
    const audio = this.audioTarget
    audio.dataset.src = src
    audio.src = src
    audio.preload = "auto"
    const seek = () => { audio.currentTime = position }
    if (audio.readyState >= 1) seek()
    else audio.addEventListener("loadedmetadata", seek, { once: true })
  }

  #play() {
    this.#say("")
    const started = this.audioTarget.play()
    started?.catch?.((error) => {
      this.#say(error?.name === "NotAllowedError" ? this.refusedLabelValue : this.errorLabelValue)
    })
  }

  // The host's audio is the party's clock: play, pause and seek report at once,
  // and a running player reports every ten seconds so a guest who joins late
  // lands where the host is, not where the host last pressed something.
  #bindHost() {
    const audio = this.audioTarget
    const report = () => this.#report(!audio.paused)
    audio.addEventListener("play", report)
    audio.addEventListener("pause", report)
    audio.addEventListener("seeked", report)
    audio.addEventListener("ended", () => this.#advance())
    this.heartbeat = setInterval(() => { if (!audio.paused) report() }, this.constructor.HEARTBEAT_MS)
  }

  #advance() {
    const current = Number(this.hasSyncTarget ? this.syncTarget.dataset.trackId : 0)
    const index = this.queueValue.indexOf(current)
    const next = this.queueValue[index + 1]
    this.advancing = Boolean(next)
    if (next) this.#send({ track_id: next, position_seconds: 0, playing: true })
    else this.#report(false)
  }

  #report(playing) {
    this.#send({ position_seconds: Math.floor(this.audioTarget.currentTime || 0), playing })
  }

  #send(fields) {
    if (!this.syncUrlValue) return
    const body = new FormData()
    body.append("_method", "patch")
    for (const [key, value] of Object.entries(fields)) body.append(key, String(value))
    const token = document.querySelector("meta[name='csrf-token']")?.content
    fetch(this.syncUrlValue, {
      method: "POST",
      body,
      headers: { "X-CSRF-Token": token || "", Accept: "text/vnd.turbo-stream.html, text/html" },
      credentials: "same-origin"
    }).catch(() => { /* the next heartbeat tries again */ })
  }

  #say(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
