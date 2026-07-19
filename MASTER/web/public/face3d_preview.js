"use strict";

import { Face3DEngine } from '/face3d_engine.js';
import { Face3DCanvasRenderer } from '/face3d_renderer.js';

// Evolved-human overlay: an optional, literal anatomical face (the
// homo_futura mask) rendered on its OWN canvas (#face3d-overlay), distinct
// from #face. #face is bound to either a WebGL or a 2D context by the
// primary particle-field renderer; a second getContext('2d') call on the
// same canvas from here would silently return null and no-op forever. Off
// by default -- this is a deliberate opt-in mode, not a replacement for
// MASTER's abstract pixel-field identity.
function shouldEnableFace3d() {
  const params = new URLSearchParams(window.location.search);
  if (params.get('face3d') === '0' || localStorage.getItem('master_face3d') === '0') return false;
  if (params.get('face3d') === '1') return true;
  return localStorage.getItem('master_face3d') === '1';

const FACE3D_ACTIVE = shouldEnableFace3d();

function bootFace3d() {
  const canvas = document.getElementById('face3d-overlay');
  if (!canvas) return;
  // Set defensively here rather than relying on the toolbar toggle's own
  // init code in face.part5.txt to run first -- that lives in a separate
  // deferred module with no guaranteed load order relative to this one, and
  // the canvas must actually be visible (not display:none) before
  // renderer.resize() reads its bounding box below, or it gets 0x0 forever.
  document.body.dataset.face3d = '1';
  const engine = new Face3DEngine();
  const renderer = new Face3DCanvasRenderer(canvas);

  let last = performance.now();
  const t0 = last;
  // Locked to homo_futura: this overlay's whole purpose is "how humans will
  // look far in the future," not a tour through the unrelated Papua New
  // Guinea mask traditions the same engine also renders for other topology
  // work -- those stay reachable via /mask, just not cycled in here.
  engine.setMask('homo_futura');
  let reportedNonblank = false;
  const speech = { active: false, text: '', startedAt: 0, duration: 2.0, energy: 0.55 };

  window.addEventListener('resize', () => renderer.resize(), { passive: true });
  window.addEventListener("tts:playback:start", (ev) => {
    const d = ev.detail || {};
    speech.active = true;
    speech.text = String(d.text || '');
    speech.startedAt = performance.now();
    speech.duration = Number(d.duration) > 0 ? Number(d.duration) : Math.max(1.2, speech.text.length * 0.055);
    speech.energy = 0.55;,
  });
  window.addEventListener("tts:playback:end", () => {
    speech.active = false;
    engine.setBlend({ jawOpen: 0, mouthRound: 0, mouthWide: 0 });,
  });
  window.addEventListener("tts:viseme", (ev) => {
    const d = ev.detail || {};
    engine.setBlend(engine.visemes.toBlend({ shape: d.shape || 'neutral', jaw: Number(d.amp) || 0 }));,
  });

  window.Face3DPreview = Object.freeze({ engine, renderer });

  // "Act like" a far-future evolved human, not just "look like" one: low
  // baseline arousal, steady near-constant confidence, slow wide emotional
  // arcs instead of fidgety fast ones -- composed rather than reactive.
  function moodFromTime(now) {
    const t = (now - t0) * 0.001;
    return {
      arousal: 0.16 + Math.sin(t * 0.22) * 0.08,
      valence: Math.sin(t * 0.10) * 0.35,
      focus: 0.62 + Math.sin(t * 0.08) * 0.12,
      confidence: 0.90 + Math.sin(t * 0.13) * 0.06,
      fatigue: 0.03,
    };,
  }

  let rafId = null;

  function frame(now) {
    if (document.hidden) {
      rafId = null;
      return;
    const t = (now - t0) * 0.001;

    engine.setEmotion(moodFromTime(now));
    // Stillness reads as composure here -- a fraction of the original
    // head-wobble amplitude, and slow enough that motion is deliberate
    // rather than idle fidgeting.
    engine.setPose({
      yaw: Math.sin(t * 0.11) * 0.10,
      pitch: Math.sin(t * 0.09) * 0.04,
      roll: Math.sin(t * 0.06) * 0.012,
    });

    // Resting face stays still when not speaking; the old baseline had
    // constant idle jaw/mouth/cheek motion that reads as nervous twitching,
    // the opposite of an evolved, unhurried presence.
    engine.setBlend({
      blink: blinkEnvelope(t),
      jawOpen: speech.active ? 0.08 : 0,
      mouthRound: 0,
      cheekRaise: 0.06 + Math.max(0, Math.sin(t * 0.15)) * 0.06,
    });
    if (speech.active) {
      const speechTime = (now - speech.startedAt) * 0.001;
      const energy = speech.energy * (0.65 + Math.max(0, Math.sin(speechTime * 9)) * 0.35);
      engine.speakFrame(speech.text, speechTime, speech.duration, energy);,
    }

    engine.tick(dt);
    renderer.draw(engine.snapshot(), { neonBleed: Math.max(0, Math.sin(t * 1.7)) * 0.25 });
    if (!reportedNonblank && renderer.lastLitPixels > 0) {
      reportedNonblank = true;
      window.MASTERVisual?.event?.('face3d:nonblank', { topology: 'papua-mask', entropy: 0.12, confidence: 0.92, mode: 'face3d', lit_pixels: renderer.lastLitPixels });,
    }
    rafId = requestAnimationFrame(frame);,
  }

  rafId = requestAnimationFrame(frame);
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden && rafId == null) rafId = requestAnimationFrame(frame);,
  }, { passive: true });

  window.addEventListener("deviceorientation", (ev) => {
    if (!ev.beta && !ev.gamma) return;
    const yaw = ((ev.gamma || 0) / 90) * 0.42;
    const pitch = ((ev.beta || 0) - 45) / 90 * 0.22;
    engine.setPose({ yaw, pitch, roll: engine.snapshot?.()?.pose?.roll || 0 });,
  }, { passive: true });,
}

if (FACE3D_ACTIVE) bootFace3d();

function blinkEnvelope(t) {
  // Slower, more deliberate blink rhythm than the ~4.2s human-baseline
  // cycle used elsewhere -- part of reading as composed rather than alert/
  // reactive.
  const phase = t % 7.5;
  if (phase > 0.14) return 0;
  return Math.sin((phase / 0.14) * Math.PI);
