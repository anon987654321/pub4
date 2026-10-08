// MASTER sparse gravitational face field.
// One projection, one frame clock, and one semantic vocabulary. The field is
// intentionally void-first: particles describe the face instead of filling it.
(() => {
  "use strict";

  const CONTRACT = window.MASTER_FACE_CONTRACT || {};
  const SPATIAL = CONTRACT.spatial || {};
  const SPEC = SPATIAL.sparse_field || {};
  const MODES = Object.freeze({
    idle:      { count: 48,  activity: 0.12, void: 0.94, drift: 0.10, orbit: 0.18 },
    listening: { count: 88,  activity: 0.42, void: 0.82, drift: 0.18, orbit: 0.28 },
    thinking:  { count: 148, activity: 0.72, void: 0.66, drift: 0.28, orbit: 0.48 },
    working:   { count: 124, activity: 0.66, void: 0.70, drift: 0.24, orbit: 0.42 },
    speaking:  { count: 116, activity: 0.78, void: 0.70, drift: 0.22, orbit: 0.38 },
    warning:   { count: 78,  activity: 0.58, void: 0.78, drift: 0.34, orbit: 0.56 },
    error:     { count: 58,  activity: 0.86, void: 0.82, drift: 0.62, orbit: 0.88 },
    sleeping:  { count: 22,  activity: 0.05, void: 0.98, drift: 0.03, orbit: 0.08 },
    ready:     { count: 60,  activity: 0.24, void: 0.90, drift: 0.12, orbit: 0.20 }
  });

  let THREE = null;
  let root = null;
  let layer = null;
  let points = null;
  let pointGeometry = null;
  let pointMaterial = null;
  let ghostPoints = null;
  let ghostGeometry = null;
  let ghostMaterial = null;
  let trailLines = null;
  let trailGeometry = null;
  let trailMaterial = null;
  let ringPoints = null;
  let ringGeometry = null;
  let ringMaterial = null;
  let attached = false;
  let loading = false;
  let pointerActive = false;
  const pointer = { x: 0, y: 0 };
  const maxParticles = Number(SPEC.max_particles || 260);
  const mobileParticles = Number(SPEC.mobile_max_particles || 140);
  const positions = new Float32Array(maxParticles * 3);
  const velocities = new Float32Array(maxParticles * 3);
  const targets = new Float32Array(maxParticles * 3);
  const sizes = new Float32Array(maxParticles);
  const opacity = new Float32Array(maxParticles);
  const phase = new Float32Array(maxParticles);
  const groups = new Uint8Array(maxParticles);
  const ghosts = [];
  const trails = [];
  const resonance = { active: false, at: 0, kind: "", energy: 0.0, seed: 0 };
  const semantic = { kind: "idle", at: 0, energy: 0, x: 0, y: 0, z: 0 };
  const motion = { resolve: 0, bloom: 0, collapse: 0, fragment: 0 };

  const clamp = (v, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, Number(v) || 0));
  const smooth = (a, b, x) => {
    const t = clamp((x - a) / Math.max(0.0001, b - a));
    return t * t * (3 - 2 * t);
  };
  const seeded = (i, salt = 0) => {
    const n = Math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
    return n - Math.floor(n);
  };
  const now = () => performance.now();

  function modeProfile(state) {
    const mode = String(state?.mode || document.documentElement.dataset.masterMode || "idle").toLowerCase();
    return MODES[mode] || MODES.idle;
  }

  function addAnchor(i, x, y, z, group = 0) {
    const j = i * 3;
    targets[j] = x;
    targets[j + 1] = y;
    targets[j + 2] = z;
    positions[j] = x;
    positions[j + 1] = y;
    positions[j + 2] = z;
    groups[i] = group;
    phase[i] = seeded(i, 31.7) * Math.PI * 2;
    sizes[i] = 0.032 + seeded(i, 12.1) * 0.040;
    opacity[i] = 0;
  }

  function faceAnchor(i) {
    const q = seeded(i, 3.2);
    const r = seeded(i, 4.7);
    const side = seeded(i, 9.1) < 0.5 ? -1 : 1;
    const choice = q;

    // Eye wells are rings, never filled centers.
    if (choice < 0.18) {
      const eye = side;
      const a = r * Math.PI * 2;
      const radius = 0.20 + seeded(i, 5.5) * 0.10;
      return [eye * 0.48 + Math.cos(a) * radius, 0.36 + Math.sin(a) * radius * 0.52, -0.02 + (seeded(i, 6.2) - 0.5) * 0.24, 1];
    }

    // Brow arcs leave the eye wells visually open.
    if (choice < 0.31) {
      const eye = side;
      const a = Math.PI * (0.15 + r * 0.68);
      return [eye * (0.40 + r * 0.12), 0.58 + Math.cos(a) * 0.14, -0.08, 2];
    }

    // Mouth is a border, never a filled patch.
    if (choice < 0.45) {
      const a = r * Math.PI * 2;
      const x = Math.cos(a) * (0.28 + 0.06 * Math.sin(a * 2));
      const y = -0.46 + Math.sin(a) * 0.08;
      return [x, y, 0.10 + Math.abs(Math.cos(a)) * 0.04, 3];
    }

    // Nose is a sparse bridge and tip.
    if (choice < 0.55) {
      const t = r;
      return [(seeded(i, 7.9) - 0.5) * 0.05, 0.22 - t * 0.60, 0.13 + t * 0.05, 4];
    }

    // Cheekbone ribbons exist in three depths to imply volume without filling space.
    if (choice < 0.72) {
      const a = (r - 0.5) * Math.PI;
      const x = side * (0.54 + Math.cos(a) * 0.18);
      const y = 0.02 + Math.sin(a) * 0.20;
      return [x, y, (seeded(i, 8.5) - 0.5) * 0.34, 5];
    }

    // Jaw / chin are broken into fragments, not a continuous outline.
    if (choice < 0.84) {
      const a = Math.PI * (0.10 + r * 0.82);
      return [Math.cos(a) * 0.66, -0.14 - Math.abs(Math.sin(a)) * 0.43, -0.08, 6];
    }

    // Forehead and crown are the sparsest region.
    return [
      (r - 0.5) * 0.95,
      0.70 + seeded(i, 11.4) * 0.32,
      (seeded(i, 13.2) - 0.5) * 0.45,
      7
    ];
  }

  function fragmentAnchor(i) {
    const a = seeded(i, 21.1) * Math.PI * 2;
    const r = 1.15 + Math.pow(seeded(i, 22.7), 0.62) * 1.55;
    return [
      Math.cos(a) * r,
      Math.sin(a) * r * 0.72,
      (seeded(i, 24.1) - 0.5) * 1.0,
      8
    ];
  }

  function buildAnchors() {
    for (let i = 0; i < maxParticles; i += 1) {
      const a = i < Math.floor(maxParticles * 0.82) ? faceAnchor(i) : fragmentAnchor(i);
      addAnchor(i, a[0], a[1], a[2], a[3]);
    }
  }

  function makeShader() {
    pointMaterial = new THREE.ShaderMaterial({
      uniforms: {
        uColor: { value: new THREE.Color(getComputedStyle(document.documentElement).getPropertyValue("--c-accent").trim() || "#d8d6e0") },
        uTime: { value: 0 },
        uSize: { value: 1.0 },
        uOpacity: { value: 0.72 },
        uEnergy: { value: 0.25 }
      },
      vertexShader: [
        "attribute float aSize;",
        "attribute float aOpacity;",
        "varying float vOpacity;",
        "uniform float uSize;",
        "void main(){",
        "  vec4 mv = modelViewMatrix * vec4(position,1.0);",
        "  gl_Position = projectionMatrix * mv;",
        "  gl_PointSize = max(1.0, aSize * uSize * 42.0 / max(1.0, -mv.z));",
        "  vOpacity = aOpacity;",
        "}"
      ].join("\n"),
      fragmentShader: [
        "varying float vOpacity;",
        "uniform float uOpacity;",
        "uniform float uEnergy;",
        "uniform vec3 uColor;",
        "void main(){",
        "  vec2 p = gl_PointCoord - 0.5;",
        "  float d = length(p);",
        "  float soft = smoothstep(0.52, 0.05, d);",
        "  float core = smoothstep(0.25, 0.0, d);",
        "  float a = soft * vOpacity * uOpacity * (0.72 + core * 0.65 + uEnergy * 0.2);",
        "  if(a < 0.008) discard;",
        "  gl_FragColor = vec4(uColor,a);",
        "}"
      ].join("\n"),
      transparent: true,
      depthWrite: false,
      depthTest: true
    });
  }

  function build() {
    const face = window.MASTER_FACE;
    if (!THREE || !face?.scene || !face?.renderer) return false;
    if (layer) return true;

    root = face.head || face.scene;
    layer = new THREE.Group();
    layer.name = "master-sparse-gravitational-field";
    root.add(layer);

    buildAnchors();

    pointGeometry = new THREE.BufferGeometry();
    pointGeometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
    pointGeometry.setAttribute("aSize", new THREE.BufferAttribute(sizes, 1));
    pointGeometry.setAttribute("aOpacity", new THREE.BufferAttribute(opacity, 1));

    makeShader();
    points = new THREE.Points(pointGeometry, pointMaterial);
    points.frustumCulled = false;
    points.renderOrder = 3;
    layer.add(points);

    ghostGeometry = new THREE.BufferGeometry();
    ghostGeometry.setAttribute("position", new THREE.Float32BufferAttribute(new Float32Array(48 * 3), 3));
    ghostGeometry.setAttribute("aSize", new THREE.Float32BufferAttribute(new Float32Array(48), 1));
    ghostGeometry.setAttribute("aOpacity", new THREE.Float32BufferAttribute(new Float32Array(48), 1));
    ghostMaterial = pointMaterial.clone();
    ghostMaterial.uniforms = THREE.UniformsUtils.clone(pointMaterial.uniforms);
    ghostMaterial.uniforms.uOpacity.value = 0.32;
    ghostPoints = new THREE.Points(ghostGeometry, ghostMaterial);
    ghostPoints.frustumCulled = false;
    ghostPoints.renderOrder = 2;
    layer.add(ghostPoints);

    trailGeometry = new THREE.BufferGeometry();
    trailGeometry.setAttribute("position", new THREE.Float32BufferAttribute(new Float32Array(24 * 6), 3));
    trailMaterial = new THREE.LineBasicMaterial({
      color: pointMaterial.uniforms.uColor.value,
      transparent: true,
      opacity: 0.22,
      depthWrite: false
    });
    trailLines = new THREE.LineSegments(trailGeometry, trailMaterial);
    trailLines.renderOrder = 1;
    layer.add(trailLines);

    ringGeometry = new THREE.BufferGeometry();
    ringGeometry.setAttribute("position", new THREE.Float32BufferAttribute(new Float32Array(56 * 3), 3));
    ringMaterial = new THREE.PointsMaterial({
      color: pointMaterial.uniforms.uColor.value,
      size: 1.8,
      transparent: true,
      opacity: 0,
      depthWrite: false
    });
    ringPoints = new THREE.Points(ringGeometry, ringMaterial);
    ringPoints.renderOrder = 4;
    layer.add(ringPoints);

    document.documentElement.dataset.faceParticleField = "sparse";
    return true;
  }

  function isMobile() {
    return matchMedia?.("(max-width: 767px)")?.matches || Number(navigator.hardwareConcurrency || 8) <= 4;
  }

  function captureGhosts(state) {
    const count = state?.mode === "speaking" ? 8 : 4;
    for (let n = 0; n < count; n += 1) {
      const i = Math.floor(seeded(Date.now() + n, 93) * Math.min(maxParticles, 180));
      const j = i * 3;
      ghosts.push({
        x: positions[j], y: positions[j + 1], z: positions[j + 2],
        size: sizes[i] * 1.8,
        born: now(),
        life: state?.mode === "error" ? 2800 : 1700
      });
    }
    while (ghosts.length > 48) ghosts.shift();
  }

  function addTrail() {
    const start = {
      x: (seeded(trails.length, 51) - 0.5) * 1.0,
      y: (seeded(trails.length, 53) - 0.5) * 0.9,
      z: 0.22
    };
    const end = {
      x: (seeded(trails.length, 57) - 0.5) * 1.9,
      y: (seeded(trails.length, 61) - 0.5) * 1.6,
      z: -0.18
    };
    trails.push({ start, end, kind: "evidence", energy: 0.6, born: now(), life: 1300 });
    while (trails.length > 12) trails.shift();
  }

  function resonate(kind = "law", energy = 0.6) {
    resonance.active = true;
    resonance.at = now();
    resonance.kind = String(kind);
    resonance.energy = clamp(energy);
    resonance.seed += 1;
    semantic.kind = String(kind);
    semantic.at = resonance.at;
    semantic.energy = clamp(energy);
    semantic.x = kind === "law" ? 0 : kind === "evidence" ? 0.18 : 0;
    semantic.y = kind === "law" ? 0.34 : kind === "evidence" ? -0.08 : 0.06;
    semantic.z = 0.14;
    motion.bloom = Math.max(motion.bloom, clamp(energy));
    if (kind === "reflection" || kind === "proof") motion.resolve = 1;
    captureGhosts(window.MASTER_FACE?.State || {});
    if (kind === "evidence" || kind === "proof") addTrail();
  }

  function pointerForce(targetX, targetY, px, py, mode) {
    const dx = targetX - px;
    const dy = targetY - py;
    const d = Math.hypot(dx, dy);
    if (d > 0.95) return [targetX, targetY];
    const force = (1 - d / 0.95) * 0.22;
    const sign = /error|warning/.test(String(mode || "").toLowerCase()) ? 1 : -1;
    return [targetX + dx * force * sign, targetY + dy * force * sign];
  }

  function updateGhosts(time) {
    const pos = ghostGeometry?.attributes?.position;
    const size = ghostGeometry?.attributes?.aSize;
    const alpha = ghostGeometry?.attributes?.aOpacity;
    if (!pos || !size || !alpha) return;

    const alive = ghosts.filter((ghost) => time - ghost.born < ghost.life);
    ghosts.splice(0, ghosts.length, ...alive);
    for (let i = 0; i < 48; i += 1) {
      const ghost = ghosts[i];
      if (!ghost) {
        pos.setXYZ(i, 0, 0, -10);
        size.setX(i, 0);
        alpha.setX(i, 0);
        continue;
      }
      const life = 1 - (time - ghost.born) / ghost.life;
      pos.setXYZ(i, ghost.x, ghost.y, ghost.z);
      size.setX(i, ghost.size * (0.8 + life * 0.8));
      alpha.setX(i, Math.max(0, life * 0.36));
    }
    pos.needsUpdate = size.needsUpdate = alpha.needsUpdate = true;
  }

  function updateTrails(time) {
    const pos = trailGeometry?.attributes?.position;
    if (!pos) return;
    let cursor = 0;
    trails.forEach((trail) => {
      const life = 1 - (time - trail.born) / trail.life;
      if (life <= 0) return;
      pos.setXYZ(cursor++, trail.start.x, trail.start.y, trail.start.z);
      pos.setXYZ(cursor++, trail.end.x, trail.end.y, trail.end.z);
    });
    while (cursor < 24) {
      pos.setXYZ(cursor++, 0, 0, -10);
      pos.setXYZ(cursor++, 0, 0, -10);
    }
    pos.needsUpdate = true;
    trailMaterial.opacity = trails.length ? 0.05 + Math.max(...trails.map((t) => 1 - (time - t.born) / t.life), 0) * 0.24 : 0;
    trails.splice(0, trails.length, ...trails.filter((trail) => time - trail.born < trail.life));
  }

  function updateRing(time) {
    if (!ringGeometry || !ringMaterial) return;
    const pos = ringGeometry.attributes.position;
    const age = time - resonance.at;
    if (!resonance.active || age > 1600) {
      ringMaterial.opacity = 0;
      return;
    }
    const life = 1 - age / 1600;
    const radius = 0.50 + (1 - life) * (0.28 + resonance.energy * 0.38);
    const y = resonance.kind === "evidence" ? -0.08 : resonance.kind === "law" ? 0.34 : 0.0;
    for (let i = 0; i < 56; i += 1) {
      const a = i / 56 * Math.PI * 2;
      const jitter = Math.sin(i * 7.3 + resonance.seed) * 0.02 * resonance.energy;
      pos.setXYZ(i, Math.cos(a) * (radius + jitter), y + Math.sin(a) * radius * 0.46, 0.16 + Math.sin(a) * 0.10);
    }
    pos.needsUpdate = true;
    ringMaterial.opacity = life * (0.12 + resonance.energy * 0.48);
  }

  function update(time) {
    if (!layer && !loading) attach();
    if (!layer || !points) return;

    const face = window.MASTER_FACE;
    const state = window.MASTER_FACE_STATE?.snapshot?.() || face?.State || {};
    const profile = modeProfile(state);
    const mobile = isMobile();
    const maxActive = mobile ? mobileParticles : maxParticles;
    const distanceDensity = clamp((6.8 - cameraDistance) / 2.4, 0.34, 1);
    const requested = Math.min(maxActive, Math.max(14, Math.round(profile.count * Number(SPEC.density_scale || 1) * distanceDensity)));
    const focus = clamp(state.focus ?? state.attention ?? 0.8);
    const confidence = clamp(state.confidence ?? 0.86);
    const risk = clamp(state.risk ?? 0);
    const reduced = Boolean(state.reducedMotion) || matchMedia?.("(prefers-reduced-motion: reduce)")?.matches;
    const cameraDistance = Number(face?.camera?.position?.length?.() || 5.2);
    const distanceReveal = clamp((6.6 - cameraDistance) / 2.8, 0.18, 1);
    const reveal = Math.max(distanceReveal, 0.35 + focus * 0.65);
    const semanticAge = Math.max(0, time - semantic.at);
    const semanticLive = semanticAge < 2400 ? 1 - semanticAge / 2400 : 0;
    const gather = state.mode === "thinking" || state.mode === "working" ? (0.05 + profile.activity * 0.16) * focus : 0;
    const voiceFilament = state.mode === "speaking" ? (0.10 + (Number(state.arousal) || 0) * 0.22) : 0;
    const breath = reduced ? 0 : Math.sin(time * 0.00035) * (0.012 + profile.activity * 0.018);
    const tide = reduced ? 0 : Math.sin(time * 0.00042 + state.entropy * 4.0) * profile.drift;
    const mouseX = Number(face?.State?.mouseX || 0) * 0.65;
    const mouseY = Number(face?.State?.mouseY || 0) * 0.65;
    const isPointer = pointerActive;

    pointMaterial.uniforms.uTime.value = time * 0.001;
    pointMaterial.uniforms.uEnergy.value = profile.activity + risk * 0.4;
    pointMaterial.uniforms.uOpacity.value = reduced ? 0.42 : 0.78;

    for (let i = 0; i < maxParticles; i += 1) {
      const j = i * 3;
      const active = i < requested;
      const baseX = targets[j];
      const baseY = targets[j + 1];
      const baseZ = targets[j + 2];
      let tx = baseX;
      let ty = baseY;
      let tz = baseZ;

      if (groups[i] === 8) {
        const orbit = profile.orbit * (1.0 + seeded(i, 71) * 0.8);
        const a = phase[i] + time * 0.00010 * orbit;
        const radius = 1.0 + seeded(i, 72) * 1.4;
        tx = Math.cos(a) * radius;
        ty = Math.sin(a) * radius * 0.72;
        tz = Math.sin(a * 1.7) * 0.48;
      }

      // Collapse, fragment and resolve are the face's large semantic motions.
      if (state.mode === "sleeping") {
        tx *= 0.16; ty *= 0.16; tz -= 0.48;
      } else if (state.mode === "error") {
        tx += Math.sin(time * 0.0011 + phase[i]) * 0.10 * profile.drift;
        ty += Math.cos(time * 0.0013 + phase[i]) * 0.08 * profile.drift;
        tz += Math.sin(time * 0.0009 + phase[i]) * 0.10;
      } else {
        tx += breath * (1 + Math.abs(baseY));
        ty += tide * 0.03;
        if (state.mode === "listening" && groups[i] === 5) {
          const earBloom = 0.06 + profile.activity * 0.10;
          tx += Math.sign(baseX || 1) * earBloom;
          ty += Math.sin(phase[i]) * earBloom * 0.4;
        }
        if (state.mode === "ready" && groups[i] !== 8) {
          tx *= 1.0 + Math.sin(time * 0.0005 + phase[i]) * 0.012;
        }
      }

      // Deterministic asymmetry: tiny stable offsets, never a perfect synthetic mirror.
      const asym = (seeded(i, 81) - 0.5) * Number(SPEC.asymmetry || 0.028);
      tx += asym * (groups[i] === 5 ? 1.4 : 0.8);
      ty += asym * 0.65;

      if (isPointer) {
        const magnet = pointerForce(tx, ty, pointer.x, pointer.y, state.mode);
        tx = magnet[0];
        ty = magnet[1];
      } else if (pointerActive) {
        pointerActive = false;
      }

      const spring = reduced ? 0.24 : 0.08 + profile.activity * 0.035;
      velocities[j] = velocities[j] * 0.90 + (tx - positions[j]) * spring;
      velocities[j + 1] = velocities[j + 1] * 0.90 + (ty - positions[j + 1]) * spring;
      velocities[j + 2] = velocities[j + 2] * 0.90 + (tz - positions[j + 2]) * spring;
      positions[j] += velocities[j];
      positions[j + 1] += velocities[j + 1];
      positions[j + 2] += velocities[j + 2];

      const rank = active ? 1 : 0;
      const well = groups[i] === 1 || groups[i] === 3 ? 1.18 : 1.0;
      const targetOpacity = rank * (0.36 + profile.activity * 0.50) * (0.46 + reveal * 0.54) * (0.74 + confidence * 0.26) / Math.max(0.2, profile.void * well);
      opacity[i] += (targetOpacity - opacity[i]) * 0.08;
      sizes[i] = (0.026 + seeded(i, 12.1) * 0.034) * (1 + profile.activity * 0.45) * (groups[i] === 8 ? 0.72 : 1.0);
    }

    pointGeometry.attributes.position.needsUpdate = true;
    pointGeometry.attributes.aSize.needsUpdate = true;
    pointGeometry.attributes.aOpacity.needsUpdate = true;

    updateGhosts(time);
    updateTrails(time);
    updateRing(time);
    document.documentElement.style.setProperty("--master-face-void", String(profile.void.toFixed(3)));
  }

  async function attach() {
    if (attached || loading) return;
    loading = true;
    try {
      const url = new URL(
        window.MASTER_ASSET_PATHS?.threeModule || "/three.face.module.js?v=1",
        document.baseURI
      ).href;
      THREE = await import(url);
      attached = build();
    } catch (error) {
      window.MASTER_LOG?.warn?.("face_sparse_field:attach", error);
    } finally {
      loading = false;
    }
  }

  function onPointer(event) {
    if (!event) return;
    pointer.x = (event.clientX / Math.max(1, innerWidth) - 0.5) * 1.7;
    pointer.y = (event.clientY / Math.max(1, innerHeight) - 0.5) * -1.0;
    pointerActive = true;
  }

  function onVisual(event) {
    const d = event.detail || {};
    const name = String(d.name || d.mode || d.phase || "").toLowerCase();
    if (/law|constitutional|resonance/.test(name) || d.law) resonate("law", d.energy ?? d.confidence ?? 0.6);
    if (/evidence|proof|anchor|verified/.test(name) || d.evidence) resonate("evidence", d.energy ?? 0.72);
    if (/reflect|repair|recompose|fix/.test(name)) resonate("reflection", 0.82);
    if (/error|veto|blocked/.test(name)) captureGhosts(d);
    if (/speech|speaking|tts/.test(name)) captureGhosts(d);
  }

  function onAudio(event) {
    const d = event.detail || {};
    if ((Number(d.onset) || 0) > 0.25 && (Number(d.rms) || 0) > 0.02) {
      if (String(window.MASTER_FACE?.State?.mode || "") === "speaking") captureGhosts(window.MASTER_FACE.State);
      addTrail();
    }
  }

  window.addEventListener("master:face-ready", attach, { passive: true });
  window.addEventListener("master:face-world-ready", attach, { passive: true });
  window.addEventListener("master:visual", onVisual, { passive: true });
  window.addEventListener("master:law", (e) => resonate("law", e.detail?.energy ?? 0.7), { passive: true });
  window.addEventListener("master:evidence", (e) => resonate("evidence", e.detail?.energy ?? 0.8), { passive: true });
  window.addEventListener("audio:update", onAudio, { passive: true });
  window.addEventListener("pointermove", onPointer, { passive: true });
  window.addEventListener("pointerleave", () => { pointerActive = false; }, { passive: true });
  if (window.MASTER_FACE) attach();

  window.MASTER_FACE_SPARSE = Object.freeze({
    update,
    attach,
    resonate,
    snapshot: () => ({
      particles: maxParticles,
      ghosts: ghosts.length,
      trails: trails.length,
      mode: window.MASTER_FACE?.State?.mode || "idle",
      void_ratio: Number(document.documentElement.style.getPropertyValue("--master-face-void") || SPEC.void_ratio || 0.8)
    })
  });
})();