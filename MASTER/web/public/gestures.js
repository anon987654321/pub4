// gestures.js — Gesture object, pointer/touch handlers, rippleAt(), dragDisplace(), handleSwipe(), handlePinch(), nod(), shake(), device motion/orientation
"use strict";

const Gesture = {
  down: false, x0: 0, y0: 0, t0: 0, x1: 0, y1: 0, longTimer: null,
  pinchDist0: 0, rotA0: 0, lastTap: 0, twoPtr: false
};

function pointerStart(e) {
  State.lastTouch = performance.now();
  Gesture.down = true;
  const p = pointerXY(e);
  Gesture.x0 = p.x; Gesture.y0 = p.y; Gesture.x1 = p.x; Gesture.y1 = p.y; Gesture.t0 = performance.now();
  Gesture.longTimer = setTimeout(() => { if (Gesture.down && dist(Gesture.x0, Gesture.y0, Gesture.x1, Gesture.y1) < 12) startSTT(); }, 420);
  Face.gazeTarget = [(p.x - W * 0.5) / W, (p.y - H * 0.5) / H];
  rippleAt(p.x, p.y);
}

function rippleAt(x, y, amp = 1.0) {
  const R2 = Face.s * Face.s * 0.36;
  for (let i = 0; i < particles.length; i++) {
    const pp = particles[i];
    const dx = pp.x - x, dy = pp.y - y, d2 = dx*dx + dy*dy;
    if (d2 < R2 && d2 > 1) {
      const f = (1 - d2 / R2) * 3.5 * amp;
      const inv = 1 / Math.sqrt(d2);
      pp.vx += dx * inv * f;
      pp.vy += dy * inv * f;
    }
  }
  if (amp >= 1.0) setTimeout(() => rippleAt(x, y, 0.3), 80);
}

function curlAt(x, y, t) {
  const k = 0.012, k2 = 0.018;
  const u = Math.sin(y * k + t * 0.0007) - Math.cos(x * k2 - t * 0.0011);
  const v = -Math.sin(x * k + t * 0.0009) + Math.cos(y * k2 + t * 0.0013);
  return [u, v];
}

function pointerMove(e) {
  if (!Gesture.down) return;
  const p = pointerXY(e);
  const movedFar = dist(Gesture.x1, Gesture.y1, p.x, p.y);
  Gesture.x1 = p.x; Gesture.y1 = p.y;
  if (dist(Gesture.x0, Gesture.y0, p.x, p.y) > 14 && Gesture.longTimer) { clearTimeout(Gesture.longTimer); Gesture.longTimer = null; }
  Face.gazeTarget = [(p.x - W * 0.5) / W, (p.y - H * 0.5) / H];
  if (movedFar > 2) dragDisplace(p.x, p.y, movedFar);
  if (e.touches && e.touches.length === 2) handlePinch(e);
}

function dragDisplace(x, y, vel) {
  const R2 = Face.s * Face.s * 0.18;
  const k = Math.min(1.2, vel * 0.08);
  for (let i = 0; i < particles.length; i++) {
    const pp = particles[i];
    const dx = pp.x - x, dy = pp.y - y, d2 = dx*dx + dy*dy;
    if (d2 < R2 && d2 > 1) {
      const f = (1 - d2 / R2) * k;
      const inv = 1 / Math.sqrt(d2);
      pp.vx += dx * inv * f;
      pp.vy += dy * inv * f;
    }
  }
}

function pointerEnd(e) {
  if (!Gesture.down) return;
  Gesture.down = false;
  if (Gesture.longTimer) { clearTimeout(Gesture.longTimer); Gesture.longTimer = null; }
  if (State.sttActive) { stopSTT(); return; }
  const dx = Gesture.x1 - Gesture.x0, dy = Gesture.y1 - Gesture.y0;
  const d = Math.hypot(dx, dy), dt = performance.now() - Gesture.t0;
  if (d < 14 && dt < 240) {
    const now = performance.now();
    if (now - Gesture.lastTap < 320) { ttsToggleMute(); Gesture.lastTap = 0; return; }
    Gesture.lastTap = now;
    if (tts.currentUtt || tts.queue.length) ttsSkip();
    return;
  }
  if (d > 60 && dt < 600) handleSwipe(dx, dy);
}

function pointerXY(e) {
  if (e.touches && e.touches[0]) return { x: e.touches[0].clientX, y: e.touches[0].clientY };
  return { x: e.clientX, y: e.clientY };
}

function dist(x1, y1, x2, y2) { return Math.hypot(x2 - x1, y2 - y1); }

function handleSwipe(dx, dy) {
  const ax = Math.abs(dx), ay = Math.abs(dy);
  if (ay > ax) {
    if (dy < 0) { sendSlash('/undo'); nod(-1); }
    else { sendSlash('/redo'); nod(+1); }
  } else {
    if (dx < 0) { sendSlash('/focus'); shake(-1); }
    else { sendSlash('/history'); shake(+1); }
  }
}

function handlePinch(e) {
  if (e.touches.length !== 2) return;
  const t0 = e.touches[0], t1 = e.touches[1];
  const d = Math.hypot(t1.clientX - t0.clientX, t1.clientY - t0.clientY);
  if (!Gesture.twoPtr) { Gesture.twoPtr = true; Gesture.pinchDist0 = d; Gesture.rotA0 = Math.atan2(t1.clientY - t0.clientY, t1.clientX - t0.clientX); return; }
  const ratio = d / Gesture.pinchDist0;
  if (ratio < 0.55) { State.mode = 'sleep'; Face.dispersionTarget = -1.0; }
  else if (ratio > 1.6) { State.mode = 'idle'; Face.dispersionTarget = 0; }
  const a = Math.atan2(t1.clientY - t0.clientY, t1.clientX - t0.clientX);
  const da = a - Gesture.rotA0;
  if (Math.abs(da) > 0.4) cyclePalette(da > 0 ? 1 : -1);
}

function nod(dir) { Face.pitchTarget = dir * 0.28; setTimeout(() => Face.pitchTarget = 0, 380); }
function shake(dir) { Face.yawTarget = dir * 0.32; setTimeout(() => Face.yawTarget = -Face.yawTarget, 180); setTimeout(() => Face.yawTarget = 0, 380); }
function sendSlash(cmd) { try { fetch(`/chat/message?message=${encodeURIComponent(cmd)}`, { method: 'GET' }); } catch (e) {} }

let lastShake = 0, lastAccel = [0, 0, 0];
if (window.DeviceMotionEvent) {
  window.addEventListener('devicemotion', (e) => {
    const a = e.accelerationIncludingGravity || e.acceleration;
    if (!a) return;
    const dx = a.x - lastAccel[0], dy = a.y - lastAccel[1], dz = a.z - lastAccel[2];
    const m = Math.hypot(dx, dy, dz);
    lastAccel = [a.x, a.y, a.z];
    const now = performance.now();
    if (m > 24 && now - lastShake > 800) { lastShake = now; vortex(); ttsSkip(); State.mode = 'idle'; Face.dispersionTarget = 0; }
  });
}

function vortex() { Face.vortex = 1.0; Face.dispersionTarget = 0.6; setTimeout(() => Face.dispersionTarget = 0, 700); }

if (window.DeviceOrientationEvent) {
  window.addEventListener('deviceorientation', (e) => {
    if (e.gamma != null) State.tiltX = e.gamma / 90;
    if (e.beta != null) State.tiltY = (e.beta - 45) / 90;
  });
}
