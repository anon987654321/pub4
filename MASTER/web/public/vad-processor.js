"use strict";
class VadProcessor extends AudioWorkletProcessor {
  constructor() { super(); this._silence = 0; this._speaking = false; }
  process(inputs) {
    const ch = inputs[0]?.[0];
    if (!ch) return true;
    let energy = 0;
    for (let i = 0; i < ch.length; i++) energy += ch[i] * ch[i];
    energy /= ch.length;
    const loud = energy > 0.0006;
    if (loud) {
      this._silence = 0;
      if (!this._speaking) { this._speaking = true; this.port.postMessage({ type: 'speech_start', energy }); }
    } else {
      this._silence++;
      if (this._speaking && this._silence > 25) {
        this._speaking = false; this.port.postMessage({ type: 'speech_end' });
      }
    }
    this.port.postMessage({ type: 'energy', energy });
    return true;
  }
}
registerProcessor('vad-processor', VadProcessor);
