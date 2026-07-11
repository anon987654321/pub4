// @stimulus-components/sound@2.0.1 downloaded from https://unpkg.com/@stimulus-components/sound@2.0.1/dist/stimulus-sound.mjs

import { Controller } from "@hotwired/stimulus";
const _Sound = class _Sound extends Controller {
  connect() {
    this.sound = new Audio(this.urlValue);
  }
  play() {
    this.sound.play();
  }
  pause() {
    this.sound.pause();
  }
  reset() {
    this.sound.pause(), this.sound.load();
  }
  volume({ params }) {
    this.sound.volume = params.volume;
  }
  muted({ params }) {
    this.sound.muted = params.muted;
  }
  loop({ params }) {
    this.sound.loop = params.loop;
  }
};
_Sound.values = {
  url: String
};
let Sound = _Sound;
export {
  Sound as default
};
