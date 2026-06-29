"use strict";

import { Face3DEngine } from '/face3d_engine.js';
import { Face3DCanvasRenderer } from '/face3d_renderer.js';

function shouldEnableFace3d() {
  const params = new URLSearchParams(window.location.search);
  if (params.get('face3d') === '0' || localStorage.getItem('master_face3d') === '0') return false;
  if (params.get('face3d') === '1') return true;
  const desktop = matchMedia('(min-width: 1024px)').matches;
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  return desktop && !reducedMotion;
}

const FACE3D_ACTIVE = shouldEnableFace3d();

function bootFace3d() {
  const canvas = document.getElementById('face');
  const engine = new Face3DEngine();
  const renderer = new Face3DCanvasRenderer(canvas);

  let last = performance.now();
  const t0 = last;
  let maskIdx = 0;
  const masks = ['sepik', 'asmat', 'baining', 'tolai', 'neutral'];
  let reportedNonblank = false;
  const speech = { active: false, text: '', startedAt: 0, duration: 2.0, energy: 0.55 };

  window.addEventListener('resize', () => renderer.resize(), { passive: true });
  window.addEventListener("tts:playback:start", (ev) => {
    const d = ev.detail || {};
    speech.active = true;
    speech.text = String(d.text || '');
    speech.startedAt = performance.now();
    speech.duration = Number(d.duration) > 0 ? Number(d.duration) : Math.max(1.2, speech.text.length * 0.055);
    speech.energy = 0.55;
  });
  window.addEventListener("tts:playback:end", () => {
    speech.active = false;
    engine.setBlend({ jawOpen: 0, mouthRound: 0, mouthWide: 0 });
  });
  window.addEventListener("tts:viseme", (ev) => {
    const d = ev.detail || {};
    engine.setBlend(engine.visemes.toBlend({ shape: d.shape || 'neutral', jaw: Number(d.amp) || 0 }));
  });

  window.Face3DPreview = Object.freeze({ engine, renderer });

  function moodFromTime(now) {
    const t = (now - t0) * 0.001;
    return {
      arousal: 0.30 + Math.sin(t * 0.7) * 0.20,
      valence: Math.sin(t * 0.33) * 0.65,
      focus: 0.45 + Math.sin(t * 0.23) * 0.25,
      confidence: 0.80 + Math.sin(t * 0.41) * 0.18,
      fatigue: 0.08 + Math.max(0, Math.sin(t * 0.17)) * 0.20
    };
  }

  function frame(now) {
    const dt = Math.min(50, now - last);
    last = now;
    const t = (now - t0) * 0.001;

    if (t > (maskIdx + 1) * 10) {
      maskIdx = (maskIdx + 1) % masks.length;
      engine.setMask(masks[maskIdx]);
    }

    engine.setEmotion(moodFromTime(now));
    engine.setPose({
      yaw: Math.sin(t * 0.37) * 0.34,
      pitch: Math.sin(t * 0.29) * 0.13,
      roll: Math.sin(t * 0.19) * 0.04
    });

    engine.setBlend({
      blink: blinkEnvelope(t),
      jawOpen: 0.08 + Math.max(0, Math.sin(t * 3.2)) * 0.18,
      mouthRound: Math.max(0, Math.sin(t * 1.6)) * 0.35,
      cheekRaise: Math.max(0, Math.sin(t * 0.8)) * 0.22
    });
    if (speech.active) {
      const speechTime = (now - speech.startedAt) * 0.001;
      const energy = speech.energy * (0.65 + Math.max(0, Math.sin(speechTime * 9)) * 0.35);
      engine.speakFrame(speech.text, speechTime, speech.duration, energy);
    }

    engine.tick(dt);
    renderer.draw(engine.snapshot(), { neonBleed: Math.max(0, Math.sin(t * 1.7)) * 0.25 });
    if (!reportedNonblank && renderer.lastLitPixels > 0) {
      reportedNonblank = true;
      window.MASTERVisual?.event?.('face3d:nonblank', { topology: 'papua-mask', entropy: 0.12, confidence: 0.92, mode: 'face3d', lit_pixels: renderer.lastLitPixels });
    }
    requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);
}

if (FACE3D_ACTIVE) bootFace3d();

function blinkEnvelope(t) {
  const phase = t % 4.2;
  if (phase > 0.10) return 0;
  return Math.sin((phase / 0.10) * Math.PI);
}
