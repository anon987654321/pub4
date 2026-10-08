import { Controller } from "@hotwired/stimulus"

// Records a voice note into the composer's own file field, so the message goes
// through the same create path as a photo or a line of text — no second
// endpoint, no upload of its own.
//
// messages.duration_seconds and Message#voice? shipped, the thread already
// renders message_type "audio" with an <audio> element, and nothing anywhere
// could produce one: there was no recorder.
export default class extends Controller {
  static targets = ["button", "status", "file", "duration", "type"]
  static values = { maxSeconds: Number, recordLabel: String, stopLabel: String }

  connect() {
    // A browser without MediaRecorder or without a secure context keeps the
    // rest of the composer: the button goes, the text field stays.
    if (!navigator.mediaDevices || typeof MediaRecorder === "undefined") {
      this.element.hidden = true
    }
  }

  disconnect() {
    this.#stopTracks()
  }

  toggle() {
    if (this.recorder?.state === "recording") {
      this.#stop()
    } else {
      this.#start()
    }
  }

  async #start() {
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch (error) {
      this.#say(this.element.dataset.deniedText || "")
      return
    }
    this.chunks = []
    this.startedAt = Date.now()
    this.recorder = new MediaRecorder(this.stream)
    this.recorder.ondataavailable = (event) => {
      if (event.data?.size > 0) this.chunks.push(event.data)
    }
    this.recorder.onstop = () => this.#finish()
    this.recorder.start()
    if (this.hasStopLabelValue) this.buttonTarget.textContent = this.stopLabelValue
    // A recording nobody stops would run until the tab closes and then upload
    // whatever it collected, so the cap is enforced here rather than trusted.
    const max = this.hasMaxSecondsValue ? this.maxSecondsValue : 120
    this.timer = setTimeout(() => this.#stop(), max * 1000)
  }

  #stop() {
    clearTimeout(this.timer)
    if (this.recorder && this.recorder.state !== "inactive") this.recorder.stop()
  }

  #finish() {
    this.#stopTracks()
    const seconds = Math.max(1, Math.round((Date.now() - this.startedAt) / 1000))
    const blob = new Blob(this.chunks, { type: this.recorder.mimeType || "audio/webm" })
    const file = new File([blob], `voice-${seconds}s.webm`, { type: blob.type })
    const transfer = new DataTransfer()
    transfer.items.add(file)
    this.fileTarget.files = transfer.files
    this.durationTarget.value = seconds
    this.typeTarget.value = "audio"
    if (this.hasRecordLabelValue) this.buttonTarget.textContent = this.recordLabelValue
    this.#say(`${seconds}s`)
  }

  #stopTracks() {
    this.stream?.getTracks().forEach((track) => track.stop())
    this.stream = null
  }

  #say(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
