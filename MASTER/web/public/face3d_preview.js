"use strict";

import { Face3DEngine } from '/face3d_engine.js';
import { Face3DCanvasRenderer } from '/face3d_renderer.js';

const enabled = new URLSearchParams(window.location.search).get('face3d') === '1';

if (enabled) {
  const canvas = document.getElementById('face');
  const engine = new Face3DEngine();
  const renderer = new Face3DCanvasRenderer(canvas);

  let last = performance.now();
  let t0 = last;
  let maskIdx = 0;
  const masks = ['sepik', 'asmat', 'baining', 'tolai', 'neutral'];

  window.addEventListener('resize', () => renderer.resize(), { passive: true });

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

    engine.tick(dt);
    renderer.draw(engine.snapshot(), { neonBleed: Math.max(0, Math.sin(t * 1.7)) * 0.25 });
    requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);
}

function blinkEnvelope(t) {
  const phase = t % 4.2;
  if (phase > 0.10) return 0;
  return Math.sin((phase / 0.10) * Math.PI);
}
