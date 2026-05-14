// fx.js — FX object, chromaticPulse(), datamosh(), mandalaLock(), cutBlack(), tickFX(), all drawXxx() functions, tickParticles(), drawParticles(), frame() render loop
"use strict";

const FX = {
  anaglyph: 0, anaglyphTarget: 0,
  ghostMirror: 0,
  chromatic: 0,
  cutBlack: 0,
  mandala: 0, mandalaPhase: 0,
  datamosh: 0, datamoshFrames: 0,
  scanline: 0,
  embers: false
};

function chromaticPulse() { FX.chromatic = 1.0; }
function datamosh() { FX.datamosh = 1.0; FX.datamoshFrames = 6; }
function mandalaLock() { FX.mandala = 1.0; FX.mandalaPhase = 0; }
function cutBlack() { FX.cutBlack = 1.0; }

function tickFX(dt) {
  if (analyser && freqData) {
    const bass = (freqData[1] + freqData[2] + freqData[3]) / (3 * 255);
    FX.anaglyphTarget = bass * 6;
    if (bass > 0.85) cutBlack();
  }
  FX.anaglyph += (FX.anaglyphTarget - FX.anaglyph) * 0.18;
  FX.ghostMirror += ((State.mode === 'speaking' ? 0.35 : 0) - FX.ghostMirror) * 0.06;
  FX.chromatic *= 0.86;
  FX.cutBlack *= 0.4;
  FX.mandala *= 0.97;
  FX.mandalaPhase += dt * 0.0018;
  if (FX.datamoshFrames > 0) FX.datamoshFrames--; else FX.datamosh *= 0.85;
  FX.scanline = (State.mode === 'thinking' || State.mode === 'rain') ? 0.4 : 0;
  FX.embers = (State.mood === 'curious' || State.mode === 'speaking');
}

function drawGhostMirror() {
  if (FX.ghostMirror < 0.02) return;
  ctx.save();
  ctx.globalAlpha = FX.ghostMirror;
  ctx.translate(0, Face.cy * 2);
  ctx.scale(1, -1);
  ctx.fillStyle = `rgba(${palette.highlight},0.5)`;
  for (let i = 0; i < particles.length; i += 2) {
    const p = particles[i];
    ctx.fillRect(p.x | 0, p.y | 0, 1, 1);
  }
  ctx.restore();
}

function drawAnaglyph() {
  if (FX.anaglyph < 0.3) return;
  const off = FX.anaglyph | 0;
  ctx.globalCompositeOperation = 'screen';
  ctx.fillStyle = 'rgba(255,40,40,0.18)';
  for (let i = 0; i < particles.length; i += 3) { const p = particles[i]; ctx.fillRect((p.x | 0) - off, p.y | 0, 1, 1); }
  ctx.fillStyle = 'rgba(40,200,255,0.18)';
  for (let i = 0; i < particles.length; i += 3) { const p = particles[i]; ctx.fillRect((p.x | 0) + off, p.y | 0, 1, 1); }
  ctx.globalCompositeOperation = 'source-over';
}

function drawChromatic() {
  if (FX.chromatic < 0.05) return;
  const r = Face.s * 1.1;
  ctx.strokeStyle = `rgba(255,80,80,${FX.chromatic * 0.18})`;
  ctx.lineWidth = 1; ctx.beginPath(); ctx.arc(Face.cx - 2, Face.cy, r, 0, Math.PI * 2); ctx.stroke();
  ctx.strokeStyle = `rgba(80,200,255,${FX.chromatic * 0.18})`;
  ctx.beginPath(); ctx.arc(Face.cx + 2, Face.cy, r, 0, Math.PI * 2); ctx.stroke();
}

function drawMandala() {
  if (FX.mandala < 0.05) return;
  ctx.save();
  ctx.translate(Face.cx, Face.cy);
  ctx.strokeStyle = `rgba(${palette.accent},${FX.mandala * 0.5})`;
  ctx.lineWidth = 1;
  const arms = 8;
  for (let a = 0; a < arms; a++) {
    ctx.rotate((Math.PI * 2) / arms);
    ctx.beginPath();
    for (let t = 0; t < 1; t += 0.05) {
      const r = Face.s * t * 0.9;
      const x = Math.cos(t * 8 + FX.mandalaPhase) * r;
      const y = Math.sin(t * 8 + FX.mandalaPhase) * r * 0.4;
      t === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
  ctx.restore();
}

function drawScanline() {
  if (FX.scanline < 0.05) return;
  ctx.fillStyle = `rgba(0,0,0,${FX.scanline * 0.35})`;
  for (let y = 0; y < H; y += 3) ctx.fillRect(0, y, W, 1);
}

function drawCutBlack() {
  if (FX.cutBlack < 0.5) return;
  ctx.fillStyle = '#000';
  ctx.fillRect(0, 0, W, H);
}

function drawCatalogGhost() {
  ctx.fillStyle = `rgba(${palette.midtone},0.06)`;
  ctx.font = '10px ui-monospace, monospace';
  ctx.fillText(`MASTER-${State.session.toString(36).toUpperCase()}`, 8, H - 8);
}

function drawEdgePulse() {
  if (Face.edgePulse < 0.02) return;
  const r = Face.s * (1.0 + (1.0 - Face.edgePulse) * 1.6);
  const a = Face.edgePulse * 0.35;
  ctx.strokeStyle = `rgba(${palette.accent},${a})`;
  ctx.lineWidth = 1;
  ctx.beginPath(); ctx.arc(Face.cx, Face.cy, r, 0, Math.PI * 2); ctx.stroke();
}

function drawCorona() {
  if (Face.coronaFlash < 0.02) return;
  const r = Face.s * 1.35;
  ctx.strokeStyle = `rgba(240,80,60,${Face.coronaFlash})`;
  ctx.lineWidth = 2;
  ctx.beginPath(); ctx.arc(Face.cx, Face.cy, r, 0, Math.PI * 2); ctx.stroke();
}

function drawThinkingOrbit(now) {
  if (State.mode !== 'thinking') return;
  const r = Face.s * 1.05;
  const a0 = now * 0.0018;
  ctx.strokeStyle = `rgba(${palette.accent},0.22)`;
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (let i = 0; i < 22; i++) {
    const t = i / 22, a = a0 + t * Math.PI * 2;
    const x = Face.cx + Math.cos(a) * r;
    const y = Face.cy - Face.s * 0.7 + Math.sin(a) * r * 0.35;
    i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
  }
  ctx.stroke();
}

function drawVortex() {
  if (Face.vortex < 0.05) return;
  const r = Face.s * 0.6;
  ctx.strokeStyle = `rgba(${palette.accent},${Face.vortex * 0.25})`;
  ctx.lineWidth = 1;
  for (let i = 0; i < 3; i++) {
    ctx.beginPath();
    for (let t = 0; t < Math.PI * 4; t += 0.1) {
      const rr = r * (t / (Math.PI * 4));
      const a = t + Face.vortex * 2 + i * 0.6;
      const x = Face.cx + Math.cos(a) * rr;
      const y = Face.cy + Math.sin(a) * rr;
      t === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
}

function tickParticles(dt, now) {
  const cx = Face.cx, cy = Face.cy, s = Face.s;
  const rot = Face.rot, cosR = Math.cos(rot), sinR = Math.sin(rot);
  const yaw = Face.yaw + State.tiltX * 0.45 + Math.sin(now * 0.00022) * 0.06;
  const pitch = Face.pitch + State.tiltY * 0.30;
  const cosY = Math.cos(yaw), sinY = Math.sin(yaw);
  const cosP = Math.cos(pitch), sinP = Math.sin(pitch);
  const disp = Face.dispersion;
  const scale = Face.bodyScale;
  const blinkClose = Face.blink > 0.3 ? 1 : 0;
  const gazeX = Face.gaze[0] * s * 0.06;
  const gazeY = Face.gaze[1] * s * 0.06;
  const pupilK = Face.pupil;
  const browDrop = Face.brow * s * 0.06;
  const audioPunch = State.audioLevel;
  const NP = particles.length;

  for (let i = 0; i < NP; i++) {
    const p = particles[i];
    let tx = p.hx, ty = p.hy, tz = p.hz;
    if (p.zone === 'pupilL' || p.zone === 'pupilR') {
      const ex = (p.zone === 'pupilL') ? cx - s * 0.32 : cx + s * 0.32;
      const ey = cy - s * 0.10;
      tx = ex + (p.hx - ex) * pupilK + gazeX;
      ty = ey + (p.hy - ey) * pupilK + gazeY;
    }
    if (p.zone === 'eyeL' || p.zone === 'eyeR') {
      const ey = cy - s * 0.10;
      ty = ey + (p.hy - ey) * (1 - blinkClose * 0.95);
    }
    if (p.zone === 'browL' || p.zone === 'browR') ty = p.hy + browDrop;
    if (p.zone === 'scarL' || p.zone === 'scarR') {
      tx = p.hx + (Math.random() - 0.5) * audioPunch * s * 0.06;
    }
    if (p.zone === 'tasselL' || p.zone === 'tasselR') {
      tx = p.hx + State.tiltX * s * 0.08;
      ty = p.hy + Math.sin(now * 0.002 + p.hy * 0.05) * s * 0.02;
    }
    if (p.zone === 'crown') {
      tx = p.hx + Math.sin(now * 0.001 + p.hx * 0.02) * s * 0.02 * (1 + Face.dispersion);
    }
    let dx = (tx - cx) * scale, dy = (ty - cy) * scale, dz = tz * scale;
    const xR = dx * cosR - dy * sinR;
    const yR = dx * sinR + dy * cosR;
    dx = xR; dy = yR;
    const xY = dx * cosY + dz * sinY;
    const zY = -dx * sinY + dz * cosY;
    dx = xY; dz = zY;
    const yP = dy * cosP - dz * sinP;
    dy = yP;
    tx = cx + dx;
    ty = cy + dy;
    if (disp > 0) {
      const [cu, cv] = curlAt(p.x, p.y, now);
      tx += cu * s * disp * 0.08;
      ty += cv * s * disp * 0.05;
    } else if (disp < 0) {
      const k = -disp;
      tx = cx * k + tx * (1 - k);
      ty = cy * k + ty * (1 - k);
    }
    if (Face.vortex > 0.01) {
      const vdx = p.x - cx, vdy = p.y - cy;
      const va = Math.atan2(vdy, vdx) + Face.vortex * 0.25;
      const vr = Math.hypot(vdx, vdy) * (1 + Face.vortex * 0.02);
      tx = cx + Math.cos(va) * vr;
      ty = cy + Math.sin(va) * vr;
    }
    if (State.mode === 'rain') {
      p.vy += 0.04;
      if (p.y > H) { p.y = -10; p.x = Math.random() * W; p.vy = 0; }
      tx = p.x; ty = p.y + 1;
    }
    const ax = (tx - p.x) * 0.08, ay = (ty - p.y) * 0.08;
    p.vx += ax;
    p.vy += ay;
    p.vx *= 0.91; p.vy *= 0.91;
    const v2 = p.vx*p.vx + p.vy*p.vy;
    if (v2 > 1.96) { const k = 1.4 / Math.sqrt(v2); p.vx *= k; p.vy *= k; }
    for (let kk = 0; kk < 2; kk++) {
      const j = (i + 137 + kk * 257) % NP;
      const q = particles[j];
      const rdx = p.x - q.x, rdy = p.y - q.y;
      const d2 = rdx*rdx + rdy*rdy;
      if (d2 < 2.25 && d2 > 0.01) {
        const f = 0.05 / d2;
        p.vx += rdx * f; p.vy += rdy * f;
      }
    }
    p.x += p.vx; p.y += p.vy;
  }
}

function drawParticles() {
  const fog = weather.fog * 0.4;
  const alpha = State.mode === 'sleep' ? 0.35 : (State.mode === 'rain' ? 0.55 : 0.95);
  const hi = palette.highlight.split(',');
  const d = () => (Math.random() < 0.33 ? -1 : Math.random() < 0.5 ? 0 : 1);
  ctx.fillStyle = `rgba(${(+hi[0]+d())|0},${(+hi[1]+d())|0},${(+hi[2]+d())|0},${alpha - fog})`;
  for (let i = 0; i < particles.length; i++) {
    const p = particles[i];
    ctx.fillRect(p.x | 0, p.y | 0, 1, 1);
  }
  if (weather.rain > 0) {
    ctx.fillStyle = `rgba(${palette.midtone},${0.15 * weather.rain})`;
    const drops = (weather.rain * 80) | 0;
    for (let i = 0; i < drops; i++) {
      const x = (idlePulse * 200 + i * 37) % W;
      const y = ((idlePulse * 500 + i * 91) % H);
      ctx.fillRect(x | 0, y | 0, 1, 4);
    }
  }
}

let lastT = performance.now(), idlePulse = 0;
function frame(now) {
  requestAnimationFrame(frame);
  const dt = Math.min(50, now - lastT); lastT = now;
  tickPalette(now);

  Face.rot += (Face.rotTarget - Face.rot) * 0.12;
  Face.yaw += (Face.yawTarget - Face.yaw) * 0.12;
  Face.pitch += (Face.pitchTarget - Face.pitch) * 0.12;
  Face.pupil += (Face.pupilTarget - Face.pupil) * 0.10;
  Face.brow += (Face.browTarget - Face.brow) * 0.08;
  Face.dispersion += (Face.dispersionTarget - Face.dispersion) * 0.06;
  Face.gaze[0] += (Face.gazeTarget[0] - Face.gaze[0]) * 0.10;
  Face.gaze[1] += (Face.gazeTarget[1] - Face.gaze[1]) * 0.10;
  Face.breath += dt * 0.001;
  Face.heartRate = 1.0 + (State.mode === 'thinking' ? 0.6 : 0) + (State.mode === 'error' ? 1.2 : 0);
  Face.bodyScale = 1.0 + Math.sin(Face.breath * Math.PI * 2 * Face.heartRate) * 0.012;
  Face.coronaFlash *= 0.94;
  Face.edgePulse *= 0.96;
  Face.vortex *= 0.93;

  Face.blinkPhase += dt * 0.001;
  const baseInt = State.mode === 'thinking' ? 0.9 : (State.mode === 'idle' ? 5.0 : 3.0);
  const interval = baseInt * (0.4 + State.confidence * 0.6);
  if (Face.blinkPhase > interval) { Face.blinkAt = now; Face.blinkPhase = 0; }
  const blinkAge = now - (Face.blinkAt || 0);
  Face.blink = blinkAge < 140 ? Math.sin(blinkAge / 140 * Math.PI) : 0;

  const idleMs = now - State.lastTouch;
  if (idleMs > 60000 && State.mode === 'idle') State.mode = 'rain';
  if (idleMs < 1000 && State.mode === 'rain') State.mode = 'idle';

  sampleAudio();
  flock();
  tickFX(dt);
  maybeSwitchMask(now, dt);
  maybeLookAway(now);
  tickParticles(dt, now);

  ctx.fillStyle = '#000';
  ctx.fillRect(0, 0, W, H);

  drawScanline();
  drawMandala();
  drawParticles();
  drawAnaglyph();
  drawGhostMirror();
  drawEdgePulse();
  drawChromatic();
  drawThinkingOrbit(now);
  drawCorona();
  drawVortex();
  drawCatalogGhost();
  drawCutBlack();

  idlePulse += dt * 0.002;

  if (State.mode === 'idle' && idlePulse % 20 > 19.9 && FX.mandala < 0.05) mandalaLock();
}
