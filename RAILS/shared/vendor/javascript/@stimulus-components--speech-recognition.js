// @stimulus-components/speech-recognition@1.0.0 downloaded from https://unpkg.com/@stimulus-components/speech-recognition@1.0.0/dist/stimulus-speech-recognition.mjs

import { Controller } from "@hotwired/stimulus";
const _SpeechRecognitionController = class _SpeechRecognitionController extends Controller {
  constructor() {
    super(...arguments), this.recognition = null, this.isListening = !1;
  }
  connect() {
    if (this.hiddenClassName = this.hasHiddenClass ? this.hiddenClass : "hidden", !this.isSupported) {
      this.startButtonTarget.classList.add(this.hiddenClassName), this.stopButtonTarget.classList.add(this.hiddenClassName), this.hasIndicatorTarget && this.indicatorTarget.classList.add(this.hiddenClassName);
      return;
    }
    this.setupRecognition(), this.updateUI();
  }
  disconnect() {
    this.recognition?.abort(), this.recognition = null;
  }
  start() {
    !this.recognition || this.isListening || (this.recognition.start(), this.isListening = !0, this.updateUI());
  }
  stop() {
    !this.recognition || !this.isListening || (this.recognition.stop(), this.isListening = !1, this.updateUI());
  }
  get isSupported() {
    return "SpeechRecognition" in window || "webkitSpeechRecognition" in window;
  }
  setupRecognition() {
    const SpeechRecognitionAPI = window.SpeechRecognition ?? window.webkitSpeechRecognition;
    this.recognition = new SpeechRecognitionAPI(), this.recognition.continuous = !0, this.recognition.interimResults = !0, this.recognition.onresult = (event) => {
      this.inputTarget.value = Array.from(event.results).map((result) => result[0].transcript).join("");
    }, this.recognition.onend = () => {
      this.isListening && (this.isListening = !1, this.updateUI());
    }, this.recognition.onerror = (event) => {
      console.error("Speech recognition error:", event.error, event.message), this.isListening = !1, this.updateUI();
    };
  }
  updateUI() {
    this.startButtonTarget.classList.toggle(this.hiddenClassName, this.isListening), this.stopButtonTarget.classList.toggle(this.hiddenClassName, !this.isListening), this.hasIndicatorTarget && this.indicatorTarget.classList.toggle(this.hiddenClassName, !this.isListening);
  }
};
_SpeechRecognitionController.targets = ["startButton", "stopButton", "indicator", "input"], _SpeechRecognitionController.classes = ["hidden"];
let SpeechRecognitionController = _SpeechRecognitionController;
export {
  SpeechRecognitionController as default
};
