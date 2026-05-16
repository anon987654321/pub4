(() => {
  "use strict";
  const cv = document.getElementById('face');
  const ctx = cv.getContext('2d');
  let W = 0, H = 0, DPR = Math.min(window.devicePixelRatio || 1, 2);
  function resize() {
    W = window.innerWidth; H = window.innerHeight;
    cv.width = W * DPR; cv.height = H * DPR;
    cv.style.width = W + 'px'; cv.style.height = H + 'px';
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    computeZones(); assignHomes();
  }

  // Face zones (Fibonacci-sphere-projected anchors)
  const Face = {
    zones: {}, anchors: [],
    rot: 0, rotTarget: 0,
    yaw: 0, yawTarget: 0, pitch: 0, pitchTarget: 0,
    blink: 0, blinkPhase: 0,
    gaze: [0, 0], gazeTarget: [0, 0],
    pupil: 1.0, pupilTarget: 1.0,
    brow: 0, browTarget: 0,
    mouth: 'neutral', mouthMorph: 0,
    breath: 0,
    vortex: 0,
    dispersion: 0, dispersionTarget: 0,
    coronaFlash: 0,
    edgePulse: 0,
    bodyScale: 1.0,
    heartRate: 1.0,
    codespaceRatio: 0, codespaceTarget: 0
  };

  function ring(cx, cy, r, a0, a1, n, zone) {
    const out = [];
    for (let i = 0; i < n; i++) {
      const t = a0 + (a1 - a0) * (i / (n - 1));
      out.push({ x: cx + Math.cos(t) * r, y: cy + Math.sin(t) * r * 0.95, zone });
    }
    return out;
  }
  function disc(cx, cy, r, n, zone) {
    const out = [];
    const golden = Math.PI * (3 - Math.sqrt(5));
    for (let i = 0; i < n; i++) {
      const rr = r * Math.sqrt((i + 0.5) / n);
      const a = i * golden;
      out.push({ x: cx + Math.cos(a) * rr, y: cy + Math.sin(a) * rr, zone });
    }
    return out;
  }
  function line(x0, y0, x1, y1, n, zone) {
    const out = [];
    for (let i = 0; i < n; i++) {
      const t = i / (n - 1);
      out.push({ x: x0 + (x1 - x0) * t, y: y0 + (y1 - y0) * t, zone });
    }
    return out;
  }
  function mouthArc(cx, cy, w, shape, n) {
    const out = [];
    for (let i = 0; i < n; i++) {
      const t = i / (n - 1);
      const x = cx - w / 2 + w * t;
      let y = cy;
      const u = (t - 0.5) * 2;
      if (shape === 'smile')   y = cy - Math.sin(t * Math.PI) * w * 0.18 + u * u * w * 0.05;
      if (shape === 'frown')   y = cy + Math.sin(t * Math.PI) * w * 0.18 - u * u * w * 0.05;
      if (shape === 'O')       y = cy + Math.sin(t * Math.PI) * w * 0.32 - 0;
      if (shape === 'A')       y = cy + Math.sin(t * Math.PI) * w * 0.45;
      if (shape === 'E')       y = cy + Math.sin(t * Math.PI) * w * 0.08;
      if (shape === 'M')       y = cy + Math.sin(t * Math.PI) * w * 0.02;
      if (shape === 'I')       y = cy + Math.sin(t * Math.PI) * w * 0.12;
      if (shape === 'U')       y = cy + Math.sin(t * Math.PI) * w * 0.25;
      out.push({ x, y, zone: 'mouth' });
    }
    return out;
  }

  // Mask library — auto-rotates between PNG mask traditions
  // Sepik River, Asmat, Baining fire dance, Tolai Tubuan, Malagan.
  // Each builder returns a flat anchor list. Cross-fade handled below.
  const MASKS = ['sepik', 'asmat', 'baining', 'tolai', 'malagan'];
  let maskIdx = 0, maskNextIdx = 0, maskCrossfade = 1.0; // 1 = no transition
  function buildSepik(cx, cy, s) {
    const z = {};
    z.outlineL = []; z.outlineR = [];
    for (let i = 0; i < 60; i++) {
      const t = i / 59, y = cy - s * 1.45 + t * s * 2.9;
      const w = s * (0.65 * Math.sin(t * Math.PI) + 0.15);
      z.outlineL.push({ x: cx - w, y, zone: 'outlineL' });
      z.outlineR.push({ x: cx + w, y, zone: 'outlineR' });
    }
    z.crown = [];
    for (let i = 0; i < 14; i++) {
      const a = -Math.PI * 0.5 + (i - 7) * 0.12;
      const len = s * (0.7 + Math.sin(i * 1.3) * 0.25);
      for (let t = 0; t < 1; t += 0.08) {
        const r = s * 0.8 + t * len;
        z.crown.push({ x: cx + Math.cos(a) * r * 0.6, y: cy - s * 0.7 + Math.sin(a) * r, zone: 'crown' });
      }
    }
    // Sepik: hooked beak ridge — straight down then curves forward like a hornbill
    const nrPts = [];
    for (let i = 0; i < 22; i++) {
      const t = i / 21;
      nrPts.push({ x: cx, y: cy - s * 0.5 + t * s * 0.95, zone: 'noseRidge' });
    }
    for (let i = 0; i < 9; i++) {
      const t = i / 8;
      const a = -Math.PI * 0.5 + t * (Math.PI * 0.55);
      nrPts.push({ x: cx + Math.cos(a) * s * 0.13, y: cy + s * 0.45 + Math.sin(a) * s * 0.13, zone: 'noseRidge' });
    }
    z.noseRidge = nrPts;
    // nostril wings as small arcs rather than a straight bar
    z.noseFlare = ring(cx - s * 0.08, cy + s * 0.52, s * 0.06, Math.PI * 0.5, Math.PI * 1.5, 6, 'noseFlare')
                 .concat(ring(cx + s * 0.08, cy + s * 0.52, s * 0.06, -Math.PI * 0.5, Math.PI * 0.5, 6, 'noseFlare'));
    z.browL = line(cx - s * 0.55, cy - s * 0.4, cx - s * 0.12, cy - s * 0.2, 14, 'browL');
    z.browR = line(cx + s * 0.12, cy - s * 0.2, cx + s * 0.55, cy - s * 0.4, 14, 'browR');
    z.eyeL = ring(cx - s * 0.32, cy - s * 0.1, s * 0.12, 0, Math.PI * 2, 20, 'eyeL')
            .concat(ring(cx - s * 0.32, cy - s * 0.1, s * 0.07, 0, Math.PI * 2, 12, 'eyeL'));
    z.eyeR = ring(cx + s * 0.32, cy - s * 0.1, s * 0.12, 0, Math.PI * 2, 20, 'eyeR')
            .concat(ring(cx + s * 0.32, cy - s * 0.1, s * 0.07, 0, Math.PI * 2, 12, 'eyeR'));
    z.pupilL = disc(cx - s * 0.32, cy - s * 0.1, s * 0.025, 5, 'pupilL');
    z.pupilR = disc(cx + s * 0.32, cy - s * 0.1, s * 0.025, 5, 'pupilR');
    z.scarL = []; z.scarR = [];
    for (let r = 0; r < 3; r++) {
      const y = cy + s * (0.08 + r * 0.13);
      z.scarL = z.scarL.concat(line(cx - s * 0.55, y, cx - s * 0.30, y, 8, 'scarL'));
      z.scarR = z.scarR.concat(line(cx + s * 0.30, y, cx + s * 0.55, y, 8, 'scarR'));
    }
    z.mouth = mouthArc(cx, cy + s * 0.92, s * 0.7, Face.mouth, 30);
    for (let i = 0; i < 7; i++) {
      const tx = cx - s * 0.32 + i * (s * 0.64 / 6);
      z.mouth.push({ x: tx, y: cy + s * 0.88, zone: 'mouth' });
      z.mouth.push({ x: tx, y: cy + s * 0.96, zone: 'mouth' });
    }
    z.chin = line(cx - s * 0.18, cy + s * 1.15, cx, cy + s * 1.40, 8, 'chin')
            .concat(line(cx, cy + s * 1.40, cx + s * 0.18, cy + s * 1.15, 8, 'chin'));
    z.tasselL = []; z.tasselR = [];
    for (let r = 0; r < 6; r++) {
      const y = cy - s * 0.4 + r * s * 0.25;
      z.tasselL.push({ x: cx - s * 0.95, y, zone: 'tasselL' });
      z.tasselR.push({ x: cx + s * 0.95, y, zone: 'tasselR' });
    }
    return z;
  }
  // Asmat — wooden eye lozenges (diamond-carved), hornbill nosepiece, geometric incisions
  function buildAsmat(cx, cy, s) {
    const z = {};
    z.outlineL = []; z.outlineR = [];
    for (let i = 0; i < 60; i++) {
      const t = i / 59, y = cy - s * 1.3 + t * s * 2.6;
      const w = s * (0.55 - Math.abs(t - 0.5) * 0.4);
      z.outlineL.push({ x: cx - w, y, zone: 'outlineL' });
      z.outlineR.push({ x: cx + w, y, zone: 'outlineR' });
    }
    // eye lozenges — diamond (♦) shape, Met collection reference
    function lozenge(ex, ey, hw, hh, zone) {
      const pts = [];
      const n = 16;
      for (let i = 0; i < n; i++) {
        const t = i / n * Math.PI * 2;
        // lozenge: |x/hw| + |y/hh| = 1 parameterised via angle
        const cos = Math.cos(t), sin = Math.sin(t);
        const r = 1 / (Math.abs(cos) / hw + Math.abs(sin) / hh);
        pts.push({ x: ex + cos * r, y: ey + sin * r, zone });
      }
      return pts;
    }
    z.eyeL = lozenge(cx - s * 0.30, cy - s * 0.05, s * 0.18, s * 0.10, 'eyeL');
    z.eyeR = lozenge(cx + s * 0.30, cy - s * 0.05, s * 0.18, s * 0.10, 'eyeR');
    z.pupilL = disc(cx - s * 0.30, cy - s * 0.05, s * 0.04, 6, 'pupilL');
    z.pupilR = disc(cx + s * 0.30, cy - s * 0.05, s * 0.04, 6, 'pupilR');
    z.noseRidge = line(cx, cy - s * 0.3, cx, cy + s * 0.5, 22, 'noseRidge');
    // hooked nose tip
    z.noseRidge = z.noseRidge.concat(line(cx, cy + s * 0.5, cx + s * 0.18, cy + s * 0.45, 6, 'noseRidge'));
    z.mouth = ring(cx, cy + s * 0.85, s * 0.18, 0, Math.PI * 2, 18, 'mouth');
    // geometric forehead chevrons
    z.crown = [];
    for (let r = 0; r < 3; r++) {
      const y = cy - s * (0.7 + r * 0.15);
      z.crown = z.crown.concat(line(cx - s * 0.4, y, cx, y - s * 0.1, 8, 'crown'))
                        .concat(line(cx, y - s * 0.1, cx + s * 0.4, y, 8, 'crown'));
    }
    // ear/jaw bones
    z.tasselL = line(cx - s * 0.6, cy + s * 0.3, cx - s * 0.7, cy + s * 0.9, 10, 'tasselL');
    z.tasselR = line(cx + s * 0.6, cy + s * 0.3, cx + s * 0.7, cy + s * 0.9, 10, 'tasselR');
    return z;
  }
  // Baining fire dance — large white-on-black, big round eye-holes, exaggerated mouth
  function buildBaining(cx, cy, s) {
    const z = {};
    // huge round outline
    z.outlineL = []; z.outlineR = [];
    for (let i = 0; i < 70; i++) {
      const a = -Math.PI + i / 70 * Math.PI * 2;
      const r = s * 1.3;
      const p = { x: cx + Math.cos(a) * r * 0.85, y: cy + Math.sin(a) * r, zone: a < 0 ? 'outlineL' : 'outlineR' };
      (a < 0 ? z.outlineL : z.outlineR).push(p);
    }
    // Baining: giant startled round eyes with spiraling pupils (Bowers Museum ref)
    z.eyeL = ring(cx - s * 0.45, cy - s * 0.25, s * 0.30, 0, Math.PI * 2, 32, 'eyeL');
    z.eyeR = ring(cx + s * 0.45, cy - s * 0.25, s * 0.30, 0, Math.PI * 2, 32, 'eyeR');
    // spiral pupils — trace an Archimedean spiral
    const spiralEye = (ex, ey, zone) => {
      const pts = [];
      for (let i = 0; i < 28; i++) {
        const t = i / 27;
        const a = t * Math.PI * 4;
        const r = t * s * 0.20;
        pts.push({ x: ex + Math.cos(a) * r, y: ey + Math.sin(a) * r * 0.8, zone });
      }
      return pts;
    };
    z.pupilL = spiralEye(cx - s * 0.45, cy - s * 0.25, 'pupilL');
    z.pupilR = spiralEye(cx + s * 0.45, cy - s * 0.25, 'pupilR');
    // small broad nose bridge
    z.noseRidge = line(cx, cy + s * 0.05, cx, cy + s * 0.35, 12, 'noseRidge');
    // wide protruding lips — Vungvung reference: large, pronounced
    z.mouth = ring(cx, cy + s * 0.72, s * 0.48, 0, Math.PI, 26, 'mouth');
    z.mouth = z.mouth.concat(ring(cx, cy + s * 0.63, s * 0.40, 0, Math.PI, 18, 'mouth'))
                     .concat(line(cx - s * 0.48, cy + s * 0.72, cx + s * 0.48, cy + s * 0.72, 16, 'mouth'));
    // antenna-like crown protrusions
    z.crown = [];
    for (let i = 0; i < 4; i++) {
      const ax = cx + (i - 1.5) * s * 0.3;
      z.crown = z.crown.concat(line(ax, cy - s * 1.3, ax, cy - s * 1.7, 8, 'crown'));
    }
    return z;
  }
  // Tolai Tubuan — conical/triangular, wide round eyes, tassel-heavy
  function buildTolai(cx, cy, s) {
    const z = {};
    // triangular silhouette — wide bottom narrowing to point
    z.outlineL = []; z.outlineR = [];
    for (let i = 0; i < 50; i++) {
      const t = i / 49;
      const y = cy - s * 1.4 + t * s * 2.6;
      const w = s * 0.15 + t * s * 0.7;
      z.outlineL.push({ x: cx - w, y, zone: 'outlineL' });
      z.outlineR.push({ x: cx + w, y, zone: 'outlineR' });
    }
    // wide round eyes
    z.eyeL = ring(cx - s * 0.30, cy + s * 0.05, s * 0.18, 0, Math.PI * 2, 24, 'eyeL');
    z.eyeR = ring(cx + s * 0.30, cy + s * 0.05, s * 0.18, 0, Math.PI * 2, 24, 'eyeR');
    z.pupilL = disc(cx - s * 0.30, cy + s * 0.05, s * 0.06, 8, 'pupilL');
    z.pupilR = disc(cx + s * 0.30, cy + s * 0.05, s * 0.06, 8, 'pupilR');
    z.noseRidge = line(cx, cy + s * 0.25, cx, cy + s * 0.7, 14, 'noseRidge');
    z.mouth = mouthArc(cx, cy + s * 0.95, s * 0.4, 'O', 20);
    // crown — single tall point
    z.crown = line(cx, cy - s * 1.4, cx, cy - s * 1.9, 12, 'crown');
    // dense tassels both sides
    z.tasselL = []; z.tasselR = [];
    for (let r = 0; r < 10; r++) {
      const y = cy + s * (0.5 + r * 0.18);
      z.tasselL.push({ x: cx - s * (0.85 - r * 0.02), y, zone: 'tasselL' });
      z.tasselR.push({ x: cx + s * (0.85 - r * 0.02), y, zone: 'tasselR' });
    }
    return z;
  }
  // Malagan — openwork carving, multi-zone, animal-totem layers
  function buildMalagan(cx, cy, s) {
    const z = {};
    z.outlineL = []; z.outlineR = [];
    for (let i = 0; i < 55; i++) {
      const t = i / 54, y = cy - s * 1.2 + t * s * 2.4;
      const w = s * (0.6 - Math.sin(t * Math.PI * 3) * 0.08);
      z.outlineL.push({ x: cx - w, y, zone: 'outlineL' });
      z.outlineR.push({ x: cx + w, y, zone: 'outlineR' });
    }
    // beak-like nose protrusion
    z.noseRidge = line(cx, cy - s * 0.2, cx, cy + s * 0.4, 18, 'noseRidge')
                  .concat(line(cx, cy + s * 0.4, cx - s * 0.15, cy + s * 0.55, 6, 'noseRidge'));
    // narrow slit eyes
    z.eyeL = line(cx - s * 0.45, cy - s * 0.1, cx - s * 0.18, cy - s * 0.1, 14, 'eyeL');
    z.eyeR = line(cx + s * 0.18, cy - s * 0.1, cx + s * 0.45, cy - s * 0.1, 14, 'eyeR');
    z.pupilL = disc(cx - s * 0.3, cy - s * 0.1, s * 0.02, 4, 'pupilL');
    z.pupilR = disc(cx + s * 0.3, cy - s * 0.1, s * 0.02, 4, 'pupilR');
    z.mouth = line(cx - s * 0.3, cy + s * 0.7, cx + s * 0.3, cy + s * 0.7, 18, 'mouth');
    // animal-totem stacking above head — bird/fish silhouettes
    z.crown = [];
    for (let i = 0; i < 18; i++) {
      const a = i / 17;
      const y = cy - s * (1.0 + a * 0.8);
      const w = s * (0.5 - a * 0.3);
      z.crown.push({ x: cx - w, y, zone: 'crown' });
      z.crown.push({ x: cx + w, y, zone: 'crown' });
      if (i % 3 === 0) z.crown.push({ x: cx, y, zone: 'crown' });
    }
    // openwork lattice — checkerboard diamond grid (New Ireland carved lattice)
    z.scarL = []; z.scarR = [];
    const owRows = 7, owCols = 6;
    for (let r = 0; r < owRows; r++) {
      for (let c = 0; c < owCols; c++) {
        if ((r + c) % 2 !== 0) continue;
        const gx = cx - s * 0.48 + c * (s * 0.96 / (owCols - 1));
        const gy = cy - s * 0.55 + r * (s * 0.90 / (owRows - 1));
        const ox2 = Math.sin(r * 2.1 + c * 1.7) * s * 0.025;
        const oy2 = Math.cos(r * 1.3 + c * 2.3) * s * 0.018;
        const zone = gx < cx ? 'scarL' : 'scarR';
        (gx < cx ? z.scarL : z.scarR).push({ x: gx + ox2, y: gy + oy2, zone });
      }
    }
    return z;
  }
  function buildMask(name, cx, cy, s) {
    let z;
    if (name === 'asmat') z = buildAsmat(cx, cy, s);
    else if (name === 'baining') z = buildBaining(cx, cy, s);
    else if (name === 'tolai') z = buildTolai(cx, cy, s);
    else if (name === 'malagan') z = buildMalagan(cx, cy, s);
    else z = buildSepik(cx, cy, s);
    return applyZ(z, s);
  }
  // Z (depth) — anchors carry z so mask reads as solid under rotation
  const ZONE_Z = {
    pupilL:    0.22, pupilR:    0.22,
    eyeL:      0.18, eyeR:      0.18,
    browL:     0.30, browR:     0.30,
    noseFlare: 0.52,
    noseRidge: 0,   // handled by per-index ramp in applyZ
    scarL:     0.15, scarR:     0.15,
    forehead:  0.32,
    outlineL:  0.0,  outlineR:  0.0,
    chin:      0.22,
    mouth:     0.26,
    crown:     0.24,
    tasselL:   0.06, tasselR:   0.06
  };
  function applyZ(zones, s) {
    for (const [name, list] of Object.entries(zones)) {
      const base = (ZONE_Z[name] !== undefined ? ZONE_Z[name] : 0) * s;
      for (let i = 0; i < list.length; i++) {
        let zi = base;
        if (name === 'noseRidge') {
          const t = i / Math.max(1, list.length - 1);
          zi = (0.06 + t * 0.38) * s;
        } else if (name === 'crown') {
          zi = Math.sin(i * 0.71) * 0.20 * s;
        } else if (name === 'tasselL' || name === 'tasselR') {
          const t = i / Math.max(1, list.length - 1);
          zi = (0.42 + t * 0.18) * s;
        }
        list[i].z = zi;
      }
    }
    return zones;
  }
  let zonesA = null, zonesB = null;
  let maskPhase = 0, maskTransitioning = false, lastMaskSwitch = performance.now();
  function computeZones() {
    const cx = W * 0.5, cy = H * 0.50;
    const s = Math.min(W, H * 0.78) * 0.22;
    Face.cx = cx; Face.cy = cy; Face.s = s;
    zonesA = buildMask(MASKS[maskIdx], cx, cy, s);
    zonesB = buildMask(MASKS[maskNextIdx], cx, cy, s);
    Face.zones = zonesA;
    Face.anchors = [].concat(...Object.values(zonesA));
  }

  // Particles
  // Mobile budget: 2200 × 12-field × 3D transform per frame OOM'd phones.
  // 600 keeps the silhouette legible without melting the GPU/JIT.
  const COARSE = matchMedia('(pointer: coarse)').matches || Math.min(innerWidth, innerHeight) < 768;
  const N = COARSE ? 600 : 2200;
  const particles = [];
  for (let i = 0; i < N; i++) particles.push({
    x: Math.random() * 600, y: Math.random() * 600,
    vx: 0, vy: 0, px: 0, py: 0,
    hx: 0, hy: 0, hz: 0,
    hx1: 0, hy1: 0, hz1: 0,
    hx2: 0, hy2: 0, hz2: 0,
    ox: Math.sin(i * 7.13) * 0.5, oy: Math.cos(i * 11.7) * 0.5, oz: Math.sin(i * 3.97) * 0.4,
    zone: 'crown', life: 1.0,
    mass: 0.7 + Math.random() * 0.6,
    activateAt: 0,
    ao: 0
  });
  function assignHomes() {
    if (!zonesA) return;
    const A = [].concat(...Object.values(zonesA));
    const B = zonesB ? [].concat(...Object.values(zonesB)) : A;
    if (!A.length) return;
    for (let i = 0; i < particles.length; i++) {
      const a = A[i % A.length];
      const b = B[i % B.length];
      const p = particles[i];
      p.hx1 = a.x + p.ox; p.hy1 = a.y + p.oy; p.hz1 = (a.z || 0) + p.oz;
      p.hx2 = b.x + p.ox; p.hy2 = b.y + p.oy; p.hz2 = (b.z || 0) + p.oz;
      p.hx = p.hx1; p.hy = p.hy1; p.hz = p.hz1;
      p.zone = a.zone;
    }
  }
  const ZONE_PHASE_LEAD = {
    outlineL: 0, outlineR: 0, forehead: 0.12, browL: 0.22, browR: 0.22,
    eyeL: 0.38, eyeR: 0.38, pupilL: 0.52, pupilR: 0.52, mouth: 0.58, chin: 0.68
  };
  function updateHomeLerp() {
    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];
      const lead = ZONE_PHASE_LEAD[p.zone] || 0;
      const ph = lead < 1 ? Math.min(1, Math.max(0, maskPhase - lead) / (1 - lead)) : maskPhase;
      const t = easeInOutCubic(ph);
      p.hx = p.hx1 + (p.hx2 - p.hx1) * t;
      p.hy = p.hy1 + (p.hy2 - p.hy1) * t;
      p.hz = p.hz1 + (p.hz2 - p.hz1) * t;
    }
  }
  function maybeSwitchMask(now, dt) {
    if (maskTransitioning) {
      maskPhase = Math.min(1, maskPhase + dt / 3000);
      updateHomeLerp();
      if (maskPhase >= 1) {
        maskTransitioning = false;
        maskIdx = maskNextIdx;
        zonesA = zonesB;
        for (let i = 0; i < particles.length; i++) {
          const p = particles[i];
          p.hx1 = p.hx2; p.hy1 = p.hy2; p.hz1 = p.hz2;
        }
      }
      return;
    }
    const interval = State.mode === 'idle' ? 90000 : 180000;
    if (now - lastMaskSwitch > interval) {
      lastMaskSwitch = now;
      maskNextIdx = (maskIdx + 1) % MASKS.length;
      zonesB = buildMask(MASKS[maskNextIdx], Face.cx, Face.cy, Face.s);
      const B = [].concat(...Object.values(zonesB));
      for (let i = 0; i < particles.length; i++) {
        const b = B[i % B.length];
        const p = particles[i];
        p.hx2 = b.x + p.ox; p.hy2 = b.y + p.oy; p.hz2 = (b.z || 0) + p.oz;
      }
      maskPhase = 0;
      maskTransitioning = true;
      Face.vortex = 0.45;
      mandalaLock();
    }
  }

  // Palettes (time-of-day + state overlays)
  function timePalette() {
    return { shadow: '8,6,6', midtone: '100,90,90', highlight: '210,205,200', accent: '155,48,38' };
  }
  let palette = timePalette(), targetPalette = palette, palBlend = 1.0;
  function lerpRGB(a, b, t) {
    const A = a.split(',').map(Number), B = b.split(',').map(Number);
    return `${A[0]+(B[0]-A[0])*t|0},${A[1]+(B[1]-A[1])*t|0},${A[2]+(B[2]-A[2])*t|0}`;
  }
  function lerpPalette(a, b, t) {
    return { shadow: lerpRGB(a.shadow, b.shadow, t), midtone: lerpRGB(a.midtone, b.midtone, t),
             highlight: lerpRGB(a.highlight, b.highlight, t), accent: lerpRGB(a.accent, b.accent, t) };
  }
  const PROVIDER_TINT = {
    claude:   { shadow: '14,8,6',   midtone: '160,80,60',  highlight: '230,150,110', accent: '230,100,70' },
    deepseek: { shadow: '6,10,14',  midtone: '60,90,130',  highlight: '120,160,200', accent: '110,170,220' },
    gemini:   { shadow: '12,8,16',  midtone: '110,80,140', highlight: '180,150,220', accent: '170,120,230' },
    gpt:      { shadow: '6,14,10',  midtone: '60,130,90',  highlight: '140,210,170', accent: '120,220,160' }
  };
  const VERDICT_TINT = {
    pass:    { shadow: '8,14,8',  midtone: '60,130,80',  highlight: '140,210,160', accent: '120,220,140' },
    veto:    { shadow: '20,4,4',  midtone: '180,40,40',  highlight: '240,90,70',   accent: '255,80,60'   },
    unclear: { shadow: '20,14,4', midtone: '180,140,40', highlight: '240,200,90',  accent: '250,200,80'  }
  };
  function fadePaletteTo(p, ms = 600) {
    targetPalette = p; palBlend = 0; palStart = performance.now(); palDur = ms;
  }
  let palStart = performance.now(), palDur = 600;

  function tickPalette(now) {
    if (palBlend < 1) {
      const t = Math.min(1, (now - palStart) / palDur);
      palBlend = easeInOutCubic(t);
      palette = lerpPalette(palette, targetPalette, palBlend < 1 ? 0.04 : 1.0);
      if (t >= 1) { palette = targetPalette; palBlend = 1; }
    }
  }
  const easeOutCubic   = t => 1 - Math.pow(1 - t, 3);
  const easeOutQuart   = t => 1 - Math.pow(1 - t, 4);
  const easeInOutCubic = t => t < 0.5 ? 4*t*t*t : 1 - Math.pow(-2*t + 2, 3) / 2;

  // State
  const State = {
    mode: 'idle', // idle|listening|thinking|speaking|ack|reject|error|sleep|rain
    mood: 'idle', model: '', provider: '', modelName: '',
    lastTouch: performance.now(),
    sttActive: false, sttInterim: '',
    confidence: 1.0,
    audioLevel: 0,
    tiltX: 0, tiltY: 0,
    session: Math.floor(Math.random() * 1e9),
    prevBass: 0
  };

  const MOOD_PALETTE = {
    tense:   { shadow: '8,12,20',  midtone: '70,90,130',   highlight: '140,160,200', accent: '120,150,220' },
    curious: { shadow: '18,14,6',  midtone: '150,110,50',  highlight: '220,185,120', accent: '230,160,80'  },
    focused: { shadow: '14,10,8',  midtone: '100,70,55',   highlight: '185,145,115', accent: '210,120,80'  },
    weary:   { shadow: '10,10,12', midtone: '80,80,95',    highlight: '150,145,165', accent: '160,140,185' }
  };

  // Audio (ambient pad + analyser)
  let actx = null, analyser = null, freqData = null, padGain1 = null, padGain2 = null, osc1 = null, osc2 = null;
  const MOOD_FREQ = {
    focused:[110.00, 164.81], curious:[123.47, 196.00], tense:[130.81, 207.65],
    weary:[98.00, 146.83], idle:[110.00, 164.81]
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
    // Beat-sync blink: sharp bass spike triggers blink within one frame
    const bass3 = (freqData[1] + freqData[2] + freqData[3]) / (3 * 255);
    if (bass3 > 0.75 && bass3 - State.prevBass > 0.2) Face.blinkAt = performance.now();
    State.prevBass = bass3;
    return State.audioLevel;
  }

  // TTS — server-side edge-tts via /chat/tts
  // fetch MP3 → decodeAudioData → AudioBufferSourceNode through the
  // existing analyser so particle reactivity works identically.
  const tts = { muted: false, queue: [], model: '', playing: false, currentSrc: null };
  const SENT_BREAK = /([.!?…]+["'\u201D]?\s+|[\n]{2,})/;

  function unlockTTS() {
    if (actx && actx.state === 'suspended') actx.resume();
  }

  function enqueueSpeech(text) {
    if (tts.muted) return;
    const clean = text.replace(/```[\s\S]*?```/g, '').replace(/[*_`~]/g, '').trim();
    if (!clean) return;
    tts.queue.push(clean);
    ttsTick();
  }

  function ttsTick() {
    if (tts.muted || tts.playing) return;
    const text = tts.queue.shift();
    if (text) playServerTTS(text);
  }

  async function playServerTTS(text) {
    tts.playing = true;
    duck(true); State.mode = 'speaking';
    try {
      const body = new URLSearchParams({ text, voice: 'osman', style: 'auto' });
      const resp = await fetch('/chat/tts', { method: 'POST', body });
      if (!resp.ok) throw new Error(resp.status);
      const arrayBuf = await resp.arrayBuffer();
      if (!actx) initAudio();
      const audioBuf = await actx.decodeAudioData(arrayBuf);
      const src = actx.createBufferSource();
      src.buffer = audioBuf;
      src.connect(analyser);
      tts.currentSrc = src;
      const CHARS_PER_SEC = 13;
      let elapsed = 0;
      const ti = setInterval(() => { elapsed += 0.08; driveViseme(text, Math.floor(elapsed * CHARS_PER_SEC)); }, 80);
      src.onended = () => {
        clearInterval(ti);
        tts.playing = false; tts.currentSrc = null;
        duck(false); setMouth('neutral');
        if (State.mode === 'speaking') State.mode = 'idle';
        ttsTick();
      };
      src.start();
    } catch (_e) {
      tts.playing = false; tts.currentSrc = null;
      duck(false);
      if (State.mode === 'speaking') State.mode = 'idle';
      ttsTick();
    }
  }

  function ttsSkip() {
    if (tts.currentSrc) { try { tts.currentSrc.stop(); } catch (_e) {} tts.currentSrc = null; }
    tts.queue.length = 0; tts.playing = false;
    duck(false); setMouth('neutral');
  }

  function ttsToggleMute() {
    tts.muted = !tts.muted;
    if (tts.muted) ttsSkip();
    Face.coronaFlash = tts.muted ? 0.6 : 0.3;
  }
  function driveViseme(text, idx) {
    const c = (text[idx] || '').toLowerCase();
    if ('aeiou'.indexOf(c) >= 0) setMouth(c.toUpperCase());
    else if ('mbpfwv'.indexOf(c) >= 0) setMouth('M');
    else if (c === ' ' || c === '.') setMouth('neutral');
    else setMouth('E');
  }
  function setMouth(shape) {
    if (Face.mouth === shape) return;
    Face.mouth = shape;
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    let m = mouthArc(cx, cy + s * 0.92, s * 0.7, shape, 30);
    // teeth tick marks (mask signature)
    for (let i = 0; i < 7; i++) {
      const tx = cx - s * 0.32 + i * (s * 0.64 / 6);
      m.push({ x: tx, y: cy + s * 0.88, zone: 'mouth' });
      m.push({ x: tx, y: cy + s * 0.96, zone: 'mouth' });
    }
    Face.zones.mouth = m;
    Face.anchors = [].concat(...Object.values(Face.zones));
    assignHomes();
  }

  // STT (long-press to talk)
  let recognition = null;
  if ('SpeechRecognition' in window || 'webkitSpeechRecognition' in window) {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    recognition = new SR();
    recognition.continuous = false; recognition.interimResults = true;
    recognition.onresult = (e) => {
      let interim = '', final = '';
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const r = e.results[i];
        (r.isFinal ? final += r[0].transcript : interim += r[0].transcript);
      }
      State.sttInterim = interim;
      if (final.trim()) { State.sttInterim = ''; State.sttActive = false; sendMessage(final.trim()); }
    };
    recognition.onend = () => { State.sttActive = false; State.sttInterim = ''; };
    recognition.onerror = () => { State.sttActive = false; };
  }
  function startSTT() {
    if (!recognition || State.sttActive) return;
    try { recognition.start(); State.sttActive = true; State.mode = 'listening'; Face.pupilTarget = 1.4; } catch (e) {}
  }
  function stopSTT() {
    if (!recognition || !State.sttActive) return;
    try { recognition.stop(); } catch (e) {}
    Face.pupilTarget = 1.0;
  }

  // SSE chat — raw text chunks, named events for state
  let evtSrc = null;
  function sendMessage(text) {
    if (evtSrc) { try { evtSrc.close(); } catch (e) {} }
    ttsSkip();
    State.mode = 'thinking';
    Face.dispersionTarget = 0.35;
    Face.browTarget = 0.4;
    const token = new URLSearchParams(window.location.search).get('token') || '';
    const stateBlob = encodeURIComponent(`${State.mood}|${State.mode}|${((performance.now() - State.lastTouch)/1000)|0}|${palIdx}`);
    const url = `/chat/message?token=${encodeURIComponent(token)}&message=${encodeURIComponent(text)}&state=${stateBlob}`;
    evtSrc = new EventSource(url);
    let pending = '';
    evtSrc.onmessage = (ev) => {
      const raw = ev.data || '';
      if (raw === '[DONE]') {
        if (pending.trim()) enqueueSpeech(pending.trim());
        pending = '';
        State.mode = 'idle'; Face.browTarget = 0; Face.dispersionTarget = 0;
        mandalaLock();
        if (navigator.vibrate) navigator.vibrate([80]);
        try { evtSrc.close(); } catch (e) {}
        return;
      }
      if (raw.startsWith('ERROR:')) { Face.coronaFlash = 1.0; State.mode = 'error'; fadePaletteTo(VERDICT_TINT.veto); triggerSweat(); triggerChibi(); return; }
      const chunk = raw.replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
      pending += chunk;
      Face.dispersionTarget = 0;
      let m;
      while ((m = pending.match(SENT_BREAK))) {
        const cut = m.index + m[0].length;
        const sent = pending.slice(0, cut).trim();
        pending = pending.slice(cut);
        if (sent) {
          enqueueSpeech(sent); chromaticPulse();
          Face.dispersionTarget = Math.min(0.06, (Face.dispersionTarget || 0) + 0.04);
          setTimeout(() => { if (Face.dispersionTarget > 0) Face.dispersionTarget = Math.max(0, Face.dispersionTarget - 0.04); }, 250);
        }
      }
    };
    evtSrc.addEventListener('tool', (ev) => {
      try { const d = JSON.parse(ev.data); datamosh(); Face.dispersionTarget = 0.2; triggerShockEyes(); } catch (e) {}
    });
    evtSrc.addEventListener('mood', (ev) => {
      const m = (ev.data || '').trim();
      if (!m) return;
      tts.mood = m; State.mood = m; moodTone(m);
      if (MOOD_PALETTE[m]) fadePaletteTo(MOOD_PALETTE[m]);
    });
    evtSrc.addEventListener('model', (ev) => {
      const m = (ev.data || '').trim();
      if (!m) return;
      tts.model = m; State.modelName = m.split('/').pop(); applyProviderTint(m);
    });
    evtSrc.addEventListener('verdict', (ev) => {
      const v = (ev.data || '').trim();
      fadePaletteTo(VERDICT_TINT[v] || timePalette());
      pulseEdge();
      if (v === 'pass') { triggerBlush(); exprRimshot(); }
      if (v === 'veto') { triggerVein(); exprGuard(); }
    });
    evtSrc.addEventListener('confidence', (ev) => {
      const c = parseFloat(ev.data); if (isNaN(c)) return;
      State.confidence = c; Face.browTarget = 1 - c; Face.dispersionTarget = Math.max(0, (1 - c) * 0.4);
    });
    evtSrc.onerror = () => {
      Face.coronaFlash = 1.0; FX.chromatic = 8;
      State.mode = 'error'; triggerSweat();
      try { evtSrc.close(); } catch (e) {}
    };
  }

  // periodic state ping (closed-loop canvas → MASTER)
  setInterval(() => {
    if (document.hidden) return;
    const idleS = ((performance.now() - State.lastTouch) / 1000) | 0;
    const body = new URLSearchParams({
      mood: State.mood, mode: State.mode, idle: String(idleS),
      palette: String(palIdx), confidence: State.confidence.toFixed(2),
      tilt_x: State.tiltX.toFixed(2), tilt_y: State.tiltY.toFixed(2)
    });
    try { fetch('/canvas/state', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body, keepalive: true }); } catch (e) {}
  }, 8000);
  function applyProviderTint(model) {
    const m = (model || '').toLowerCase();
    const key = Object.keys(PROVIDER_TINT).find(k => m.includes(k));
    if (key) fadePaletteTo(PROVIDER_TINT[key]);
  }
  function pulseEdge() { Face.edgePulse = 1.0; }

  // Gesture detection
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
    const k = 0.012, k2 = 0.018, k3 = 0.007;
    const u = Math.sin(y*k + t*0.0007) - Math.cos(x*k2 - t*0.0011) + Math.sin(x*k3 + y*k3 + t*0.0005) * 0.4;
    const v = -Math.sin(x*k + t*0.0009) + Math.cos(y*k2 + t*0.0013) + Math.cos(y*k3 - x*k3 + t*0.0006) * 0.4;
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
  function dist(x1,y1,x2,y2) { return Math.hypot(x2-x1, y2-y1); }
  function handleSwipe(dx, dy) {
    const ax = Math.abs(dx), ay = Math.abs(dy);
    if (ay > ax) {
      if (dy < 0) { sendSlash('/undo');    nod(-1); }
      else        { sendSlash('/redo');    nod(+1); }
    } else {
      if (dx < 0) { sendSlash('/focus');   shake(-1); }
      else        { sendSlash('/history'); shake(+1); }
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

  // palette cycle (mood overrides)
  const MOOD_PALETTES = [timePalette(),
    PROVIDER_TINT.claude, PROVIDER_TINT.deepseek, PROVIDER_TINT.gemini, PROVIDER_TINT.gpt];
  let palIdx = 0;
  function cyclePalette(dir) {
    palIdx = (palIdx + dir + MOOD_PALETTES.length) % MOOD_PALETTES.length;
    fadePaletteTo(MOOD_PALETTES[palIdx], 800);
  }

  // shake to reset
  let lastShake = 0, lastAccel = [0,0,0];
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

  // tilt — iOS requires explicit permission since Safari 13
  function bindDeviceOrientation() {
    window.addEventListener('deviceorientation', (e) => {
      if (e.gamma != null) State.tiltX = e.gamma / 90;
      if (e.beta  != null) State.tiltY = (e.beta - 45) / 90;
    });
  }
  async function requestMotionPermission() {
    if (typeof DeviceOrientationEvent !== 'undefined' &&
        typeof DeviceOrientationEvent.requestPermission === 'function') {
      try { const r = await DeviceOrientationEvent.requestPermission(); if (r === 'granted') bindDeviceOrientation(); }
      catch (_e) {}
    } else if (window.DeviceOrientationEvent) {
      bindDeviceOrientation();
    }
  }

  // VAD — energy-based AudioWorklet, no ONNX dependency
  async function initVAD() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
      if (!actx) initAudio();
      await actx.audioWorklet.addModule('/vad-processor.js');
      const src = actx.createMediaStreamSource(stream);
      const node = new AudioWorkletNode(actx, 'vad-processor');
      src.connect(node);
      node.port.onmessage = ({ data }) => {
        if (data.type === 'speech_start') { State.mode = 'listening'; Face.browTarget = 0.3; }
        if (data.type === 'speech_end')   { State.mode = 'idle';      Face.browTarget = 0; }
      };
    } catch (_e) {}
  }

  // Screen Wake Lock — keep display on during sessions
  let wakeLock = null;
  async function acquireWakeLock() {
    if (!('wakeLock' in navigator)) return;
    try {
      wakeLock = await navigator.wakeLock.request('screen');
      document.addEventListener('visibilitychange', async () => {
        if (document.visibilityState === 'visible' && !wakeLock) {
          try { wakeLock = await navigator.wakeLock.request('screen'); } catch (_e) {}
        }
      });
    } catch (_e) {}
  }

  // Weather (#26) — best-effort, silent fail
  let weather = { rain: 0, fog: 0 };
  function fetchWeather() {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition((pos) => {
      const { latitude: lat, longitude: lon } = pos.coords;
      const u = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=precipitation,cloud_cover`;
      fetch(u).then(r => r.json()).then(d => {
        const c = d.current || {};
        weather.rain = Math.min(1, (c.precipitation || 0) / 3);
        weather.fog  = Math.min(1, (c.cloud_cover || 0) / 100);
      }).catch(() => {});
    }, () => {}, { timeout: 4000, maximumAge: 3600000 });
  }

  // Boids neighbor flock (light, only when idle long)
  function flock() {
    const NP = particles.length;
    const strength = State.mode === 'idle' ? 0.010 : 0.005;
    for (let i = 0; i < NP; i += 6) {
      const p = particles[i], q = particles[(i + 137) % NP];
      // Alignment: match neighbor velocity
      p.vx += (q.vx - p.vx) * strength;
      p.vy += (q.vy - p.vy) * strength;
      // Separation: push if overlapping
      const rdx = p.x - q.x, rdy = p.y - q.y, d2 = rdx*rdx + rdy*rdy;
      if (d2 < 9 && d2 > 0.01) { const f = 0.04 / d2; p.vx += rdx * f; p.vy += rdy * f; }
    }
  }

  // Aesthetic effects (Warp / Low End Theory / Flamagra)
  const FX = {
    anaglyph: 0, anaglyphTarget: 0, // R/cyan offset (bass-reactive)
    ghostMirror: 0, // Pepper's-ghost vertical second-stack alpha
    chromatic: 0, // chromatic-aberration pulse on stressed syllables
    cutBlack: 0, // 1-frame canvas clear on transient
    mandala: 0, mandalaPhase: 0, // radial symmetry lock on long silence
    datamosh: 0, datamoshFrames: 0, // velocity-hold smear on tool event
    embers: false, // ember-rise mode (warm mood)
    // Manga manpu (漫符)
    sweat: 0, // embarrassment/error — teardrop from temple
    vein: 0, // anger/reject — pulsing cross on forehead
    blush: 0, // warmth/ack/pass — rose ovals on cheeks
    noseBubbleR: 0, // sleep — growing circle from nose tip, resets on pop
    speedLines: 0, // thinking — radial streaks from face edge
    tears: 0, // sleep — cascading streams from eye centers
    shockEyes: 0, // surprise/tool — rings expand, pupils contract
    chibi: 0 // error — brief vertical squash of whole face
  };
  function chromaticPulse() { FX.chromatic = 1.0; }
  function datamosh()       { FX.datamosh  = 1.0; FX.datamoshFrames = 6; }
  function mandalaLock()    { FX.mandala   = 1.0; FX.mandalaPhase = 0; }
  function cutBlack()       { FX.cutBlack  = 1.0; }
  function triggerSweat()   { FX.sweat     = 1.0; }
  function triggerVein()    { FX.vein      = 1.0; }
  function triggerBlush()   { FX.blush     = 1.0; }
  function triggerShockEyes() { FX.shockEyes = 1.0; }
  function triggerChibi()   { FX.chibi     = 1.0; }

  // Combat and performance expression vocabulary
  // MMA guard: brow furrow + gaze lock (Muay Thai, Silat, UFC awareness posture)
  function exprGuard() {
    Face.browTarget = 0.88; Face.gazeTarget = [0, 0];
    setTimeout(() => { Face.browTarget = 0; }, 2400);
  }
  // Pre-fight stare: pupils contract, blink suppressed 3s
  function exprPreStare() {
    Face.pupilTarget = 0.52; Face.blinkPhase = -3.0;
    setTimeout(() => { Face.pupilTarget = 1.0; }, 3000);
  }
  // Muay Thai ram muay / Silat bunga: serene brow lift + slow head sway
  function exprRamMuay() {
    Face.browTarget = -0.58; Face.yawTarget = (Math.random() > 0.5 ? 1 : -1) * 0.09;
    setTimeout(() => { Face.browTarget = 0; Face.yawTarget = 0; }, 2800);
  }
  // Silat aura: dreamy gaze drift + breath-pitch sway
  function exprSilat() {
    Face.gazeTarget = [(Math.random() - 0.5) * 0.32, (Math.random() - 0.5) * 0.18];
    Face.pitchTarget = (Math.random() - 0.5) * 0.11;
    setTimeout(() => { Face.gazeTarget = [0, 0]; Face.pitchTarget = 0; }, 3600);
  }
  // Standup comedy punchline: held beat → blush + chibi pop
  function exprPunchline() {
    setTimeout(() => { triggerBlush(); triggerChibi(); }, 380);
  }
  // Rimshot: high brow flash + shock eyes
  function exprRimshot() {
    Face.browTarget = -0.92; triggerShockEyes();
    setTimeout(() => { Face.browTarget = 0; }, 1100);
  }
  // Slam/spoken-word emotional peak: blush + speed lines
  function exprSpokenWord() {
    triggerBlush(); FX.speedLines = Math.min(1, FX.speedLines + 0.72);
  }
  // Curious head-tilt: slight yaw + brow lift (universal)
  function exprCurious() {
    Face.yawTarget = (Math.random() > 0.5 ? 1 : -1) * 0.13;
    Face.browTarget = -0.42;
    setTimeout(() => { Face.yawTarget = 0; Face.browTarget = 0; }, 2000);
  }

  const Expr = { lastFire: 0, recent: [] };
  function tickPersonalityExpressions(now) {
    const mean = { speaking: 6000, thinking: 9000, idle: 22000, listening: 7000, error: 4000 }[State.mode] || 14000;
    if (now - Expr.lastFire < mean * (0.6 + Math.random() * 0.8)) return;
    Expr.lastFire = now;
    const pools = {
      thinking:  [exprGuard, exprPreStare, exprSilat, exprCurious, exprGuard],
      speaking:  [exprRimshot, exprPunchline, exprRamMuay, exprSpokenWord, exprCurious],
      idle:      [exprSilat, exprRamMuay, exprCurious],
      listening: [exprGuard, exprCurious, exprPreStare],
      error:     [exprGuard, exprPreStare]
    };
    const pool = pools[State.mode] || pools.idle;
    // Fatigue: deprioritise expressions fired in the last 4 turns
    const fresh = pool.filter(fn => Expr.recent.filter(f => f === fn).length < 2);
    const chosen = (fresh.length ? fresh : pool)[Math.floor(Math.random() * (fresh.length || pool.length))];
    chosen();
    Expr.recent.push(chosen);
    if (Expr.recent.length > 4) Expr.recent.shift();
  }

  function tickFX(dt) {
    // anaglyph follows bass
    if (analyser && freqData) {
      const bass = (freqData[1] + freqData[2] + freqData[3]) / (3 * 255);
      FX.anaglyphTarget = bass * 6;
      if (bass > 0.85) cutBlack();
    }
    FX.anaglyph += (FX.anaglyphTarget - FX.anaglyph) * 0.18;
    // ghost mirror when speaking
    FX.ghostMirror += ((State.mode === 'speaking' ? 0.35 : 0) - FX.ghostMirror) * 0.06;
    FX.chromatic *= 0.86;
    FX.cutBlack  *= 0.4;
    FX.mandala   *= 0.97;
    FX.mandalaPhase += dt * 0.0018;
    if (FX.datamoshFrames > 0) FX.datamoshFrames--; else FX.datamosh *= 0.85;
    FX.embers = (State.mood === 'curious' || State.mode === 'speaking');
    // Manga manpu ticks
    FX.sweat      *= 0.983;
    FX.vein        = State.mode === 'error' ? Math.min(1, FX.vein + 0.07) : FX.vein * 0.94;
    FX.blush       = State.mode === 'ack'   ? Math.min(1, FX.blush + 0.06) : FX.blush * 0.97;
    FX.tears       = State.mode === 'sleep' ? Math.min(1, FX.tears + 0.04) : FX.tears * 0.91;
    FX.speedLines  = State.mode === 'thinking' ? Math.min(1, FX.speedLines + 0.06) : FX.speedLines * 0.87;
    FX.shockEyes  *= 0.91;
    FX.chibi      *= 0.86;
    // nose bubble: grows during extended idle/sleep, pops and resets
    const longIdle = (performance.now() - State.lastTouch) > 55000;
    if ((State.mode === 'sleep' || longIdle) && State.mode !== 'error') {
      FX.noseBubbleR += dt * 0.012;
      if (FX.noseBubbleR > Face.s * 0.28) FX.noseBubbleR = 0;
    } else {
      FX.noseBubbleR *= 0.88;
    }
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
    ctx.fillStyle = `rgba(255,40,40,0.18)`;
    for (let i = 0; i < particles.length; i += 3) { const p = particles[i]; ctx.fillRect((p.x | 0) - off, p.y | 0, 1, 1); }
    ctx.fillStyle = `rgba(40,200,255,0.18)`;
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
    return;
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
  function drawCutBlack() {
    if (FX.cutBlack < 0.5) return;
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, W, H);
  }
  function drawCatalogGhost() {
    ctx.fillStyle = `rgba(${palette.midtone},0.06)`;
    ctx.font = '10px ui-monospace, monospace';
    ctx.fillText(`MASTER-${State.session.toString(36).toUpperCase()}`, 8, H - 18);
    if (State.modelName) ctx.fillText(State.modelName, 8, H - 8);
  }

  // Whisper voice (low-volume asides)
  function whisper(text) {
    if (tts.muted || !text) return;
    tts.queue.push(text); ttsTick();
  }
  // Boot phrases — whispered at startup
  const DMESG_PHRASES = [
    'Master booting', 'Soul loaded', 'Constitution online', 'Tools registered',
    'Pipeline armed', 'Council convened', 'Ready'
  ];

  // Render loop
  let lastT = performance.now(), idlePulse = 0, _frameSkip = 0;
  function frame(now) {
    requestAnimationFrame(frame);
    const dt = Math.min(50, now - lastT); lastT = now;
    if (State.mode === 'sleep' && dt < 20 && (++_frameSkip % 2 === 0)) return;
    tickPalette(now);

    // smooth state lerps
    Face.rot     += (Face.rotTarget - Face.rot) * 0.12;
    Face.yaw     += (Face.yawTarget - Face.yaw) * 0.12;
    Face.pitch   += (Face.pitchTarget - Face.pitch) * 0.12;
    Face.pupil   += (Face.pupilTarget - Face.pupil) * 0.10;
    Face.brow    += (Face.browTarget - Face.brow) * 0.08;
    Face.dispersion += (Face.dispersionTarget - Face.dispersion) * 0.06;
    // Saccadic profile: ballistic when far (>0.12), slow settle when close.
    const gazeDist = Math.hypot(Face.gazeTarget[0] - Face.gaze[0], Face.gazeTarget[1] - Face.gaze[1]);
    const gazeRate = gazeDist > 0.12 ? 0.30 : 0.08;
    Face.gaze[0] += (Face.gazeTarget[0] - Face.gaze[0]) * gazeRate;
    Face.gaze[1] += (Face.gazeTarget[1] - Face.gaze[1]) * gazeRate;
    tickMicrosaccades(dt);
    Face.breath  += dt * 0.001;
    Face.heartRate = 1.0 + (State.mode === 'thinking' ? 0.6 : 0) + (State.mode === 'error' ? 1.2 : 0);
    Face.bodyScale = 1.0 + Math.sin(Face.breath * Math.PI * 2 * Face.heartRate) * 0.012;
    Face.dispersionTarget += Math.sin(Face.breath * Math.PI * 2 * Face.heartRate) * 0.012;
    Face.coronaFlash    *= 0.94;
    Face.edgePulse      *= 0.96;
    Face.vortex         *= 0.93;
    Face.codespaceRatio += (Face.codespaceTarget - Face.codespaceRatio) * 0.03;

    // blink scheduler — cosine envelope, low confidence blinks more often
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
    tickPersonalityExpressions(now);
    maybeSwitchMask(now, dt);
    maybeLookAway(now);
    tickParticles(dt, now);

    // bg
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, W, H);

    drawMandala();
    drawSpeedLines();
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
    drawBlush();
    drawTears();
    drawSweat();
    drawVein();
    drawNoseBubble();

    idlePulse += dt * 0.002;

    // mandala lock auto-trigger on long silence
    if (State.mode === 'idle' && idlePulse % 20 > 19.9 && FX.mandala < 0.05) mandalaLock();
  }

  function tickParticles(dt, now) {
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    const rot = Face.rot, cosR = Math.cos(rot), sinR = Math.sin(rot);
    const yaw = Face.yaw + State.tiltX * 0.45 + Math.sin(now * 0.00022) * 0.35;
    const pitch = Face.pitch + State.tiltY * 0.30 + Math.sin(now * 0.00015) * 0.15;
    const cosY = Math.cos(yaw), sinY = Math.sin(yaw);
    const cosP = Math.cos(pitch), sinP = Math.sin(pitch);
    const disp = Face.dispersion;
    const scale = Face.bodyScale;
    const blinkClose = Face.blink > 0.3 ? 1 : 0;
    // orbicularis oculi: smile squints the lower lid, narrowing the eye opening
    const squint = Face.mouth === 'smile' ? 0.22 : 0;
    const breathPhase = Math.sin(Face.breath * Math.PI * 2 * Face.heartRate);
    const gazeX = (Face.gaze[0] + gazeJitter[0]) * s * 0.06;
    const gazeY = (Face.gaze[1] + gazeJitter[1]) * s * 0.06;
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
        ty = ey + (p.hy - ey) * (1 - blinkClose * 0.95 - squint * 0.28);
      }
      if (p.zone === 'browL' || p.zone === 'browR') ty = p.hy + browDrop;
      if (p.zone === 'scarL' || p.zone === 'scarR') {
        tx = p.hx + (Math.random() - 0.5) * audioPunch * s * 0.06;
      }
      if (p.zone === 'noseFlare') {
        ty = p.hy + breathPhase * s * 0.014; // nostril flares on inhale
        tx = p.hx + breathPhase * (p.hx > cx ? 1 : -1) * s * 0.008;
      }
      if (p.zone === 'tasselL' || p.zone === 'tasselR') {
        tx = p.hx + State.tiltX * s * 0.08;
        ty = p.hy + Math.sin(now * 0.002 + p.hy * 0.05) * s * 0.02;
      }
      if (p.zone === 'crown') {
        tx = p.hx + Math.sin(now * 0.001 + p.hx * 0.02) * s * 0.02 * (1 + Face.dispersion);
        ty = p.hy + breathPhase * (p.hx - cx) * 0.008;
      }
      // Manga: shock eyes — ring expands, pupils contract (before 3D so it respects rotation)
      if (FX.shockEyes > 0.01) {
        if (p.zone === 'eyeL' || p.zone === 'eyeR') {
          const ex = (p.zone === 'eyeL') ? cx - s * 0.32 : cx + s * 0.32;
          const ey2 = cy - s * 0.10;
          tx = ex + (tx - ex) * (1 + FX.shockEyes * 0.50);
          ty = ey2 + (ty - ey2) * (1 + FX.shockEyes * 0.50);
        } else if (p.zone === 'pupilL' || p.zone === 'pupilR') {
          const ex = (p.zone === 'pupilL') ? cx - s * 0.32 : cx + s * 0.32;
          const ey2 = cy - s * 0.10;
          tx = ex + (tx - ex) * (1 - FX.shockEyes * 0.70);
          ty = ey2 + (ty - ey2) * (1 - FX.shockEyes * 0.70);
        }
      }
      // Manga: chibi collapse — brief vertical squash, slight horizontal spread
      if (FX.chibi > 0.01) {
        ty = cy + (ty - cy) * (1 - FX.chibi * 0.52);
        tx = cx + (tx - cx) * (1 + FX.chibi * 0.18);
      }
      // 3D transform around centroid: scale → roll → yaw → pitch
      let dx = (tx - cx) * scale, dy = (ty - cy) * scale, dz = tz * scale;
      const xR = dx * cosR - dy * sinR;
      const yR = dx * sinR + dy * cosR;
      dx = xR; dy = yR;
      const xY = dx * cosY + dz * sinY;
      const zY = -dx * sinY + dz * cosY;
      dx = xY; dz = zY;
      const yP = dy * cosP - dz * sinP;
      dy = yP;
      p.sz = dz; // eye-space z — drives depth-layered rendering
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
      // Architecture #15: codebase topology — disperse face into orbital ring.
      if (Face.codespaceRatio > 0.01) {
        const phi = (i / NP) * Math.PI * 2;
        const orbitR = Math.min(W, H) * 0.38;
        const ox = cx + Math.cos(phi) * orbitR;
        const oy = cy + Math.sin(phi) * orbitR * 0.55;
        tx += (ox - tx) * Face.codespaceRatio;
        ty += (oy - ty) * Face.codespaceRatio;
      }
      if (State.mode === 'rain') {
        const windX = Math.sin(now * 0.0004) * 0.025;
        p.vx += windX; p.vy += 0.04;
        if (p.y > H) { p.y = -10; p.x = Math.random() * W; p.vx = 0; p.vy = 0; }
        tx = p.x; ty = p.y + 1;
      }
      if (State.mode === 'sleep') {
        p.vx += (Math.random() - 0.5) * 0.03;
        p.vy += (Math.random() - 0.5) * 0.02;
        p.vx += (tx - p.x) * 0.003;
        p.vy += (ty - p.y) * 0.003;
      }
      // Variable spring stiffness by zone; mass-scaled acceleration
      const ZONE_K = { pupilL: 0.14, pupilR: 0.14, eyeL: 0.12, eyeR: 0.12,
                       browL: 0.10, browR: 0.10, crown: 0.04, tasselL: 0.035, tasselR: 0.035 };
      const k = ZONE_K[p.zone] || 0.08;
      const kActive = (now >= p.activateAt) ? k : k * 0.04;
      const ax = (tx - p.x) * kActive / p.mass;
      const ay = (ty - p.y) * kActive / p.mass;
      p.vx += ax; p.vy += ay;
      // Underdamped far, overdamped near target
      const dTarget = Math.hypot(tx - p.x, ty - p.y);
      const damp = dTarget < 2 ? 0.72 : 0.91;
      p.vx *= damp; p.vy *= damp;
      // Vorticity confinement on dispersed field
      if (disp > 0.1) {
        const [cu, cv] = curlAt(p.x, p.y, now);
        const cm = Math.hypot(cu, cv);
        if (cm > 0.01) { p.vx += (cu / cm) * cm * 0.15 * disp; p.vy += (cv / cm) * cm * 0.10 * disp; }
      }
      // Velocity ceiling
      const v2 = p.vx*p.vx + p.vy*p.vy;
      if (v2 > 1.96) { const kv = 1.4 / Math.sqrt(v2); p.vx *= kv; p.vy *= kv; }
      // Sub-pixel repulsion (3 deterministic neighbors)
      for (let kk = 0; kk < 3; kk++) {
        const j = (i + 137 + kk * 181) % NP;
        const q = particles[j];
        const rdx = p.x - q.x, rdy = p.y - q.y;
        const d2 = rdx*rdx + rdy*rdy;
        if (d2 < 2.25 && d2 > 0.01) { const f = 0.05 / d2; p.vx += rdx * f; p.vy += rdy * f; }
      }
      p.px = p.x; p.py = p.y;
      p.x += p.vx; p.y += p.vy;
    }
  }

  function drawParticles() {
    const fog = weather.fog * 0.4;
    const base = State.mode === 'sleep' ? 0.35 : (State.mode === 'rain' ? 0.55 : 0.92);
    const rr = 210, gg = 205, bb = 200;
    const zT = Face.s * 0.07;

    // Thinking mode: trail at previous position
    if (State.mode === 'thinking') {
      ctx.fillStyle = `rgba(${rr},${gg},${bb},0.12)`;
      for (let i = 0; i < particles.length; i += 2) {
        const p = particles[i];
        ctx.fillRect(p.px | 0, p.py | 0, 1, 1);
      }
    }

    // Far layer — recessed: dim, 1px
    ctx.fillStyle = `rgba(${rr},${gg},${bb},${Math.max(0, base - fog - 0.40).toFixed(2)})`;
    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];
      if ((p.sz || 0) < -zT) ctx.fillRect(p.x | 0, p.y | 0, 1, 1);
    }
    // Mid layer — face surface: normal, 1px
    const dr = ((Math.random() * 8 - 4) | 0);
    ctx.fillStyle = `rgba(${rr+dr},${gg+dr},${bb+dr},${(base - fog - 0.08).toFixed(2)})`;
    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];
      const sz = p.sz || 0;
      if (sz >= -zT && sz <= zT) ctx.fillRect(p.x | 0, p.y | 0, 1, 1);
    }
    // Near layer — protruding: 2px + sub-pixel jitter
    ctx.fillStyle = `rgba(${Math.min(255,rr+10)},${Math.min(255,gg+7)},${Math.min(255,bb+2)},${(base - fog).toFixed(2)})`;
    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];
      if ((p.sz || 0) > zT) {
        const jx = (Math.random() * 0.8 - 0.4) | 0;
        const jy = (Math.random() * 0.8 - 0.4) | 0;
        ctx.fillRect((p.x + jx) | 0, (p.y + jy) | 0, 2, 2);
      }
    }
    // Weather rain overlay
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

  // Microsaccades — biological eye tremor during fixation
  // Real fixation includes ~3-5 microsaccades/second + drift; amplitude ~0.1-0.3°.
  // Modelled as random impulse + exponential decay offset over the intended gaze.
  const gazeJitter = [0, 0];
  function tickMicrosaccades(dt) {
    if (State.mode === 'sleep') return;
    const amp = State.mode === 'thinking' ? 0.038 : (State.mode === 'idle' ? 0.012 : 0.024);
    if (Math.random() < dt * 0.0035) {
      gazeJitter[0] = (Math.random() - 0.5) * amp;
      gazeJitter[1] = (Math.random() - 0.5) * amp * 0.45;
    }
    gazeJitter[0] *= 0.87;
    gazeJitter[1] *= 0.87;
  }

  // Look-aways — periodic gaze averts to break the stare
  let nextLookAway = performance.now() + 12000 + Math.random() * 6000;
  let lookAwayUntil = 0;
  function maybeLookAway(now) {
    if (State.mode !== 'idle' || (tts.currentUtt && tts.queue.length)) return;
    if (now > lookAwayUntil && now > nextLookAway) {
      Face.gazeTarget = [(Math.random() - 0.5) * 0.6, (Math.random() - 0.5) * 0.3];
      lookAwayUntil = now + 900 + Math.random() * 700;
    } else if (now > lookAwayUntil && now < nextLookAway && lookAwayUntil > 0 && now - lookAwayUntil < 200) {
      Face.gazeTarget = [0, 0];
      nextLookAway = now + 12000 + Math.random() * 8000;
      lookAwayUntil = 0;
    }
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

  // Manga manpu draw functions
  // Sweat drop: teardrop at temple — embarrassment / error
  function drawSweat() {
    if (FX.sweat < 0.05) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    const tx2 = cx - s * 0.72, ty2 = cy - s * 0.38;
    const sz = s * 0.055 * FX.sweat;
    ctx.save();
    ctx.globalAlpha = FX.sweat * 0.82;
    ctx.fillStyle = 'rgba(140,190,255,1)';
    ctx.beginPath(); ctx.arc(tx2, ty2, sz, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath();
    ctx.moveTo(tx2 - sz * 0.45, ty2 - sz * 0.2);
    ctx.quadraticCurveTo(tx2, ty2 - sz * 2.8, tx2 + sz * 0.45, ty2 - sz * 0.2);
    ctx.closePath(); ctx.fill();
    ctx.restore();
  }

  // Pulsing vein cross: anger / reject / error
  function drawVein() {
    if (FX.vein < 0.05) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    const vx = cx + s * 0.26, vy = cy - s * 0.62;
    const pulse = 1 + Math.sin(performance.now() * 0.014) * 0.28;
    const arm = s * 0.055 * pulse * FX.vein;
    ctx.save();
    ctx.globalAlpha = FX.vein * 0.88;
    ctx.strokeStyle = 'rgba(210,35,35,1)';
    ctx.lineWidth = 2; ctx.lineCap = 'round';
    // Classic manga vein: two kinked segments forming a cross
    ctx.beginPath();
    ctx.moveTo(vx - arm, vy);
    ctx.lineTo(vx - arm * 0.32, vy); ctx.lineTo(vx - arm * 0.32, vy - arm * 0.55);
    ctx.lineTo(vx, vy - arm * 0.55); ctx.lineTo(vx, vy);
    ctx.lineTo(vx, vy + arm * 0.55); ctx.lineTo(vx + arm * 0.32, vy + arm * 0.55);
    ctx.lineTo(vx + arm * 0.32, vy); ctx.lineTo(vx + arm, vy);
    ctx.stroke();
    ctx.restore();
  }

  // Blush ovals: warmth / ack / pass verdict
  function drawBlush() {
    if (FX.blush < 0.05) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    const a = FX.blush * 0.16;
    [[cx - s * 0.43, cy + s * 0.06], [cx + s * 0.43, cy + s * 0.06]].forEach(([bx, by]) => {
      const g = ctx.createRadialGradient(bx, by, 0, bx, by, s * 0.26);
      g.addColorStop(0, `rgba(220,75,100,${a})`);
      g.addColorStop(1, `rgba(220,75,100,0)`);
      ctx.fillStyle = g;
      ctx.fillRect(bx - s * 0.28, by - s * 0.20, s * 0.56, s * 0.40);
    });
  }

  // Nose bubble: growing sphere from nose tip — sleep / long idle
  function drawNoseBubble() {
    if (FX.noseBubbleR < 1.5) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    const bx = cx + s * 0.07, by = cy + s * 0.44;
    const r = FX.noseBubbleR;
    const a = Math.min(1, r / (s * 0.08)) * 0.32;
    ctx.save();
    ctx.globalAlpha = a;
    ctx.strokeStyle = `rgba(${palette.highlight},0.7)`;
    ctx.lineWidth = 1;
    ctx.beginPath(); ctx.arc(bx, by - r, r, 0, Math.PI * 2); ctx.stroke();
    // lens highlight
    ctx.fillStyle = `rgba(${palette.highlight},0.12)`;
    ctx.beginPath(); ctx.arc(bx - r * 0.28, by - r - r * 0.28, r * 0.22, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  }

  // Speed lines: radial streaks — thinking / determination
  function drawSpeedLines() { return;
    if (FX.speedLines < 0.05) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    const n = 18, now = performance.now();
    ctx.save();
    ctx.globalAlpha = FX.speedLines * 0.20;
    ctx.strokeStyle = `rgba(${palette.highlight},1)`;
    ctx.lineWidth = 1;
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + now * 0.0003;
      const r0 = s * 1.25, r1 = s * (2.0 + Math.sin(i * 1.7) * 0.3);
      ctx.beginPath();
      ctx.moveTo(cx + Math.cos(a) * r0, cy + Math.sin(a) * r0 * 0.72);
      ctx.lineTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1 * 0.72);
      ctx.stroke();
    }
    ctx.restore();
  }

  // Cascade tears: vertical streams — sleep / intense emotion
  function drawTears() {
    if (FX.tears < 0.05) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    const now = performance.now();
    ctx.save();
    ctx.globalAlpha = FX.tears * 0.52;
    ctx.strokeStyle = 'rgba(140,190,255,1)';
    ctx.lineWidth = 1.5; ctx.lineCap = 'round';
    [[cx - s * 0.32, cy - s * 0.08], [cx + s * 0.32, cy - s * 0.08]].forEach(([ex, ey]) => {
      const offset = (now * 0.048) % (s * 1.1);
      for (let d = 0; d < 3; d++) {
        const y0 = ey + (offset + d * s * 0.37) % (s * 1.1);
        ctx.beginPath();
        ctx.moveTo(ex, y0);
        ctx.lineTo(ex + (ex < cx ? -1 : 1) * s * 0.018, y0 + s * 0.11);
        ctx.stroke();
      }
    });
    ctx.restore();
  }

  // Wire events
  cv.addEventListener('pointerdown', pointerStart);
  cv.addEventListener('pointermove', pointerMove);
  cv.addEventListener('pointerup',   pointerEnd);
  cv.addEventListener('pointercancel', pointerEnd);
  document.addEventListener('pointermove', (e) => {
    if (Gesture.down || e.pointerType !== 'mouse') return;
    const lean = 0.25;
    Face.gazeTarget = [(e.clientX - W * 0.5) / W * lean, (e.clientY - H * 0.5) / H * lean];
  }, { passive: true });
  cv.addEventListener('touchstart', (e) => { if (e.touches.length === 2) { Gesture.twoPtr = false; handlePinch(e); } }, { passive: true });
  cv.addEventListener('touchmove',  (e) => { if (e.touches.length === 2) handlePinch(e); }, { passive: true });
  cv.addEventListener('touchend',   () => { Gesture.twoPtr = false; });
  window.addEventListener('resize', resize);

  document.addEventListener('mousemove', (e) => {
    if (e.buttons) return;
    Face.yawTarget   = (e.clientX / innerWidth  - 0.5) * 0.7;
    Face.pitchTarget = (e.clientY / innerHeight - 0.5) * 0.45;
  }, { passive: true });

  // Topology events from visual_bridge.js — drive codebase disperse.
  window.addEventListener('master:visual', (e) => {
    const top = (e.detail || {}).topology || '';
    Face.codespaceTarget = top === 'codebase' ? 1.0 : 0.0;
  });

  // Primer unlock
  const primer = document.getElementById('primer');
  const zshBar = document.getElementById('zsh');
  const zshIn  = document.getElementById('zin');
  function startEverything() {
    primer.classList.add('gone');
    setTimeout(() => primer.remove(), 1000);
    initAudio();
    if (actx && actx.state === 'suspended') actx.resume();
    unlockTTS();
    fetchWeather();
    requestMotionPermission();
    acquireWakeLock();
    initVAD();
    // dmesg→chat intro: stagger whispered boot phrases, then say "ready"
    DMESG_PHRASES.slice(0, -1).forEach((p, i) => setTimeout(() => whisper(p), 400 + i * 600));
    setTimeout(() => enqueueSpeech('ready'), 400 + DMESG_PHRASES.length * 600);
    Face.dispersionTarget = 0; Face.coronaFlash = 0.3;
    setTimeout(() => zshBar.classList.add('live'), 600);
    if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
  }
  primer.addEventListener('pointerdown', startEverything, { once: true });
  
  // Zsh prompt bar
  zshIn.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter') return;
    const v = zshIn.value.trim();
    if (!v) return;
    e.preventDefault();
    zshIn.value = '';
    Face.dispersionTarget = 0.25; // skeleton tension before any byte arrives
    sendMessage(v);
  });
  zshIn.addEventListener('focus', () => { State.lastTouch = performance.now(); });

  // Keyboard fallback
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') ttsSkip();
    if (e.ctrlKey && e.key === 'm') { e.preventDefault(); ttsToggleMute(); }
  });

  // boot
  resize();
  fadePaletteTo(timePalette(), 1000);
  requestAnimationFrame(frame);
})();
