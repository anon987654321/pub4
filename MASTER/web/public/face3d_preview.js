"use strict";

const face3dPaths = window.MASTER_ASSET_PATHS || {};
const engineUrl = face3dPaths.face3dEngine || "/face3d_engine.js";
const rendererUrl = face3dPaths.face3dRenderer || "/face3d_renderer.js";
// These imports run at module top level; a rejection here aborts evaluation
// before bootFace3d() can run and — without this guard — dispatches no event,
// leaving the boot state machine stuck on "face slow" with no error signal.
let Face3DEngine, Face3DCanvasRenderer;
try {
  ({ Face3DEngine } = await import(engineUrl));
  ({ Face3DCanvasRenderer } = await import(rendererUrl));
} catch (error) {
  console.error("face3d module load failed", error);
  window.__MASTER_FACE_STACK_FAILED__ = true;
  window.dispatchEvent(new CustomEvent("master:face-error", {
    detail: { message: String(error), module: "face3d_preview", stage: "import" }
  }));
  throw error;
}

function face3dDisabled() {
  const params = new URLSearchParams(window.location.search);
  return params.get("face3d") === "0" || localStorage.getItem("master_face3d") === "0";
}

function topologyMask(topology) {
  const map = {
    "papua-mask": "sepik",
    "sepik": "sepik",
    "asmat": "asmat",
    "baining": "baining",
    "tolai": "tolai",
    "neutral": "neutral",
    "serpent": "asmat",
    "neural": "baining"
  };
  return map[String(topology || "").toLowerCase()] || "sepik";
}

function primerBlocking() {
  const el = document.getElementById("primer");
  return !!(el && el.parentNode && !el.classList.contains("gone") && !el.disabled);
}

function bootFace3d() {
  if (face3dDisabled() || window.FACE3D_ACTIVE) return;

  const canvas = document.getElementById("face");
  if (!canvas) return;

  const engine = new Face3DEngine();
  const renderer = new Face3DCanvasRenderer(canvas);
  const t0 = performance.now();
  let last = t0;
  let reportedNonblank = false;
  let liveAnnounced = false;
  let bootBoost = 1.0;
  let currentMask = "sepik";
  const speech = { active: false, text: "", startedAt: 0, duration: 2.0, energy: 0.55 };
  let emotion = { arousal: 0.32, valence: 0, focus: 0.45, confidence: 0.82, fatigue: 0.08 };

  window.FACE3D_ACTIVE = true;
  window.Face3DPreview = Object.freeze({ engine, renderer });

  window.addEventListener("resize", () => renderer.resize(), { passive: true });

  window.addEventListener("master:visual", (ev) => {
    const d = ev.detail || {};
    const ex = d.expression || {};
    if (d.topology) {
      currentMask = topologyMask(d.topology);
      engine.setMask(currentMask);
    }
    emotion = {
      arousal: Number(ex.arousal ?? d.arousal ?? emotion.arousal),
      valence: Number(ex.valence ?? d.valence ?? emotion.valence),
      focus: Number(ex.focus ?? d.focus ?? emotion.focus),
      confidence: Number(d.confidence ?? ex.confidence ?? emotion.confidence),
      fatigue: Number(ex.fatigue ?? emotion.fatigue)
    };
    if (d.entropy != null) emotion.fatigue = Math.min(1, emotion.fatigue + Number(d.entropy) * 0.12);
  });

  window.addEventListener("tts:playback:start", (ev) => {
    const d = ev.detail || {};
    speech.active = true;
    speech.text = String(d.text || "");
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
    engine.setBlend(engine.visemes.toBlend({ shape: d.shape || "neutral", jaw: Number(d.amp) || 0 }));
  });

  function announceFaceLive(litPixels) {
    if (liveAnnounced) return;
    liveAnnounced = true;
    document.body.dataset.faceLive = "1";
    const badge = document.getElementById("face-live-badge");
    if (badge) {
      badge.hidden = false;
      badge.dataset.visible = "1";
    }
    const ui = document.getElementById("ui-status");
    if (ui) ui.textContent = "face live";
    window.dispatchEvent(new CustomEvent("master:face-live", { detail: { lit_pixels: litPixels } }));
    window.setTimeout(() => {
      if (primerBlocking()) return;
      delete document.body.dataset.faceLive;
      if (badge) {
        badge.dataset.visible = "0";
        window.setTimeout(() => { badge.hidden = true; }, 420);
      }
      if (ui && ui.textContent === "face live") ui.textContent = "";
    }, 3200);
  }

  function blinkEnvelope(t) {
    const phase = t % 4.2;
    if (phase > 0.10) return 0;
    return Math.sin((phase / 0.10) * Math.PI);
  }

  function frame(now) {
    if (primerBlocking() && now - last < 80) {
      requestAnimationFrame(frame);
      return;
    }
    const dt = Math.min(50, now - last);
    last = now;
    const t = (now - t0) * 0.001;
    const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

    const bridgeEmotion = window.MASTER_FACE_BLEND?.currentEmotion?.();
    if (bridgeEmotion) emotion = { ...emotion, ...bridgeEmotion };
    engine.setEmotion(emotion);
    engine.setPose({
      yaw: reduced ? 0 : Math.sin(t * 0.37) * 0.22,
      pitch: reduced ? 0 : Math.sin(t * 0.29) * 0.10,
      roll: reduced ? 0 : Math.sin(t * 0.19) * 0.03
    });

    const mouth = window.MASTER_FACE_BLEND?.current?.() || {};
    const idleJaw = 0.06 + Math.max(0, Math.sin(t * 2.8)) * 0.10;
    const jawOpen = speech.active
      ? Math.max(engine.blend.jawOpen, mouth.jawOpen ?? 0)
      : Math.max(idleJaw, mouth.jawOpen ?? 0);
    engine.setBlend({
      blink: blinkEnvelope(t),
      jawOpen,
      mouthWide: mouth.mouthWide ?? engine.blend.mouthWide,
      mouthRound: mouth.mouthRound ?? engine.blend.mouthRound,
      smile: mouth.smile ?? engine.blend.smile,
      frown: mouth.frown ?? engine.blend.frown,
      cheekRaise: Math.max(0, emotion.valence) * 0.18
    });

    if (speech.active) {
      const speechTime = (now - speech.startedAt) * 0.001;
      const energy = speech.energy * (0.65 + Math.max(0, Math.sin(speechTime * 9)) * 0.35);
      engine.speakFrame(speech.text, speechTime, speech.duration, energy);
    }

    engine.tick(dt);
    if (reportedNonblank) bootBoost = Math.max(0, bootBoost - dt * 0.00038);
    renderer.draw(engine.snapshot(), {
      neonBleed: reduced ? 0 : Math.max(0, Math.sin(t * 1.7)) * 0.18,
      bootBoost: reportedNonblank ? bootBoost : 1.0
    });

    if (!reportedNonblank && renderer.lastLitPixels > 0) {
      reportedNonblank = true;
      document.body.classList.add("face-ready");
      announceFaceLive(renderer.lastLitPixels);
      window.MASTERVisual?.event?.("face3d:nonblank", {
        topology: currentMask,
        entropy: 0.12,
        confidence: emotion.confidence,
        mode: "face3d",
        lit_pixels: renderer.lastLitPixels
      });
    }
    requestAnimationFrame(frame);
  }

  engine.setMask(currentMask);
  requestAnimationFrame(frame);
  window.MASTERVisual?.event?.("face3d:ready", { topology: currentMask, entropy: 0.16, confidence: 0.88, mode: "face3d" });
  window.setTimeout(() => {
    if (liveAnnounced) return;
    document.body.classList.add("face-ready");
    announceFaceLive(renderer.lastLitPixels || 0);
  }, 1800);
}

try {
  bootFace3d();
} catch (error) {
  console.error("face3d boot failed", error);
  window.dispatchEvent(new CustomEvent("master:face-error", { detail: { message: String(error) } }));
}