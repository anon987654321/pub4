// audio.js — AudioContext init, dual oscillators, moodTone(), duck(), sampleAudio()
"use strict";

const MOOD_FREQ = {
  focused: [110.00, 164.81], curious: [123.47, 196.00], tense: [130.81, 207.65],
  weary: [98.00, 146.83], idle: [110.00, 164.81]
};

function initAudio() {
  if (actx) return;
  try {
    actx = new (window.AudioContext || window.webkitAudioContext)();
    analyser = actx.createAnalyser(); analyser.fftSize = 256;
    freqData = new Uint8Array(analyser.frequencyBinCount);
    osc1 = actx.createOscillator(); osc1.type = 'sine'; osc1.frequency.value = 110;
    osc2 = actx.createOscillator(); osc2.type = 'sine'; osc2.frequency.value = 164.81;
    padGain1 = actx.createGain(); padGain1.gain.value = 0.025;
    padGain2 = actx.createGain(); padGain2.gain.value = 0.018;
    osc1.connect(padGain1); padGain1.connect(analyser);
    osc2.connect(padGain2); padGain2.connect(analyser);
    analyser.connect(actx.destination);
    osc1.start(); osc2.start();
  } catch (e) {}
}

function moodTone(tag) {
  if (!osc1) return;
  const f = MOOD_FREQ[tag] || MOOD_FREQ.idle;
  const t = actx.currentTime;
  osc1.frequency.linearRampToValueAtTime(f[0], t + 0.8);
  osc2.frequency.linearRampToValueAtTime(f[1], t + 0.8);
}

function duck(on) {
  if (!padGain1) return;
  const t1 = on ? 0.005 : 0.025, t2 = on ? 0.003 : 0.018;
  padGain1.gain.linearRampToValueAtTime(t1, actx.currentTime + 0.25);
  padGain2.gain.linearRampToValueAtTime(t2, actx.currentTime + 0.25);
}

function sampleAudio() {
  if (!analyser) return 0;
  analyser.getByteFrequencyData(freqData);
  let sum = 0;
  for (let i = 0; i < freqData.length; i++) sum += freqData[i];
  State.audioLevel = sum / (freqData.length * 255);
  return State.audioLevel;
}
