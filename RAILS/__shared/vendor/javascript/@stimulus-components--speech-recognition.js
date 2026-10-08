import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets=["startButton","stopButton","indicator","input"]
  static classes=["hidden"]
  connect(){this.hiddenClassName=this.hasHiddenClass?this.hiddenClass:"hidden";if(!this.isSupported){this.startButtonTarget?.classList.add(this.hiddenClassName);this.stopButtonTarget?.classList.add(this.hiddenClassName);this.indicatorTarget?.classList.add(this.hiddenClassName);return}this.setupRecognition();this.updateUI()}
  disconnect(){this.recognition?.abort();this.recognition=null}
  start(){if(!this.recognition||this.isListening)return;this.recognition.start();this.isListening=true;this.updateUI()}
  stop(){if(!this.recognition||!this.isListening)return;this.recognition.stop();this.isListening=false;this.updateUI()}
  get isSupported(){return"SpeechRecognition"in window||"webkitSpeechRecognition"in window}
  setupRecognition(){const API=window.SpeechRecognition||window.webkitSpeechRecognition;this.recognition=new API();this.recognition.continuous=true;this.recognition.interimResults=true;this.recognition.onresult=event=>{this.inputTarget.value=Array.from(event.results).map(result=>result[0].transcript).join("");this.inputTarget.dispatchEvent(new Event("input",{bubbles:true}))};this.recognition.onend=()=>{if(this.isListening){this.isListening=false;this.updateUI()}};this.recognition.onerror=()=>{this.isListening=false;this.updateUI()}}
  updateUI(){this.startButtonTarget?.classList.toggle(this.hiddenClassName,this.isListening);this.stopButtonTarget?.classList.toggle(this.hiddenClassName,!this.isListening);this.indicatorTarget?.classList.toggle(this.hiddenClassName,!this.isListening)}
}
