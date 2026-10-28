/* Additive, bounded stipple layer for the existing MASTER face.
 * It reuses the live face state and face geometry where possible. ParticleKernel,
 * the original point cloud and its render loop remain untouched.
 */
(() => {
  "use strict";

  const params = new URLSearchParams(window.location.search || "");
  const enabled = params.get("stipple") !== "0";
  const MAX_POINTS = 14_000;
  const FRAME_SAMPLE_LIMIT = 60;
  const MOBILE_FALLBACK = 420;
  const DESKTOP_FALLBACK = 1_200;
  // The nine moods live in MASTER/data/tokens.yml (face_interface.stipple.profiles) and arrive
  // as MASTER_FACE_CONTRACT; only idle is kept here so a page without the contract still draws.
  const IDLE_PROFILE = Object.freeze({ density: 0.44, ripple: 0.03, turbulence: 0.04, luminosity: 0.76, attract: 0.14 });
  const DEFAULT_POINT_SIZE = Object.freeze({
    base: 0.90, bias_scale: 0.35, bias_min: 0.25, bias_max: 1.50,
    reference_depth: 5.0, distance_min: 0.75, distance_max: 1.25,
    output_min: 1.0, output_max: 1.5
  });
  const profiles = () => window.MASTER_FACE_CONTRACT?.stipple?.profiles || {};
  const pointSizing = () => ({
    ...DEFAULT_POINT_SIZE,
    ...(window.MASTER_FACE_CONTRACT?.stipple?.point_size || {})
  });

  const overrides = {};
  let installing = false;
  let wrappedRenderer = null;
  let originalRender = null;
  let renderWrapper = null;
  let rendererCanvas = null;
  let active = null;
  let renderedFrames = 0;
  let lastFrameAt = 0;
  let lastRenderIntervalMs = null;
  const frameIntervals = [];
  let contextState = "ready";

  function reducedMotionEnabled(state = {}) {
    const canonical = window.MASTER_FACE_STATE?.reducedMotion;
    if (typeof canonical === "function") return canonical(state);
    // Compatibility fallback for an older shell without the canonical state bridge.
    const mediaReduced = Boolean(window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches);
    const declaredReduced = document.documentElement?.dataset?.reducedMotion === "1";
    const runtimeReduced = Boolean(window.MASTER_FACE?.State?.reducedMotion);
    return Boolean(state?.reducedMotion) || runtimeReduced || declaredReduced || mediaReduced;
  }

  function currentFaceState() {
    return window.MASTER_FACE_STATE?.snapshot?.() || window.MASTER_FACE?.State || {};
  }

  const clamp = (value, fallback, min = 0, max = 1) => {
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(min, Math.min(max, number)) : fallback;
  };
  const rand = (index, salt = 0) => {
    const value = Math.sin(index * 12.9898 + salt * 78.233) * 43758.5453;
    return value - Math.floor(value);
  };

  function constrainedDevice() {
    const matches = (query) => Boolean(window.matchMedia?.(query)?.matches);
    const cores = Number(window.navigator?.hardwareConcurrency || 8);
    return matches("(pointer: coarse)") || matches("(max-width: 767px)") || cores <= 4;
  }

  function pointBudget(requested) {
    const contract = window.MASTER_FACE_CONTRACT || {};
    const budget = contract.spatial?.budget || {};
    const swarm = contract.swarm || {};
    const state = currentFaceState();
    const reduced = reducedMotionEnabled(state);
    // FaceState owns the additive point split; swarm remains under spatial limits.
    const sharedBudget = window.MASTER_FACE_STATE?.renderBudget?.() || {};
    const mobile = constrainedDevice();
    const fallback = mobile ? MOBILE_FALLBACK : DESKTOP_FALLBACK;
    const totalValue = Number(sharedBudget.points ?? budget[mobile ? "mobile_points" : "desktop_points"]);
    const total = Number.isFinite(totalValue) && totalValue > 0 ? totalValue : fallback;
    const allocation = budget.point_allocation || {};
    const stippleWeight = Math.max(0.1, Number(allocation.stipple_fraction) || 0.75);
    const worldWeight = Math.max(0.1, Number(allocation.world_fraction) || 0.25);
    const fallbackShare = Math.max(1, Math.floor(total * stippleWeight / (stippleWeight + worldWeight)));
    const shared = Number(sharedBudget.stipple_points);
    const configured = Number.isFinite(shared) && shared > 0 ? shared : fallbackShare;
    let ceiling = Number.isFinite(configured) && configured > 0
      ? Math.min(MAX_POINTS, Math.floor(configured))
      : fallback;
    if (swarm.enabled === true) {
      const tokenLimit = Number(swarm.particle_budget);
      if (Number.isFinite(tokenLimit) && tokenLimit > 0) ceiling = Math.min(ceiling, Math.floor(tokenLimit));
      const spatialLimit = Number(budget[reduced ? "reduced_motion_particles" : mobile ? "mobile_particles" : "desktop_particles"]);
      if (Number.isFinite(spatialLimit) && spatialLimit > 0) ceiling = Math.min(ceiling, Math.floor(spatialLimit));
    }
    const desired = Number.isFinite(Number(requested)) && Number(requested) > 0
      ? Math.floor(Number(requested)) : ceiling;
    return Math.max(1, Math.min(desired, ceiling, MAX_POINTS));
  }

  function defaultSamples(count) {
    const samples = [];
    for (let i = 0; i < count; i += 1) {
      const q = rand(i, 1);
      const r = rand(i, 2);
      const side = rand(i, 3) < 0.5 ? -1 : 1;
      let x, y, z, zone;
      if (q < 0.17) {
        const a = r * Math.PI * 2;
        const radius = 0.18 + rand(i, 4) * 0.105;
        x = side * 0.31 + Math.cos(a) * radius;
        y = 0.17 + Math.sin(a) * radius * 0.56;
        z = 0.20 + rand(i, 5) * 0.012;
        zone = 1;
      } else if (q < 0.29) {
        const a = Math.PI * (0.14 + r * 0.72);
        x = side * (0.30 + r * 0.11);
        y = 0.38 + Math.cos(a) * 0.13;
        z = 0.16;
        zone = 2;
      } else if (q < 0.40) {
        const a = r * Math.PI * 2;
        x = Math.cos(a) * (0.21 + 0.045 * Math.sin(a * 2));
        y = -0.32 + Math.sin(a) * 0.06;
        z = 0.21 + Math.abs(Math.cos(a)) * 0.012;
        zone = 3;
      } else if (q < 0.50) {
        x = (rand(i, 6) - 0.5) * 0.045;
        y = 0.15 - r * 0.48;
        z = 0.23 + r * 0.03;
        zone = 4;
      } else {
        const xx = r * 2 - 1;
        const yy = rand(i, 7) * 2 - 1;
        const taper = 0.73 - Math.max(0, -yy) * 0.18;
        const edge = Math.sqrt(Math.max(0.04, 1 - xx * xx * 0.82 - yy * yy * 0.56));
        x = xx * taper;
        y = yy * 0.91;
        z = 0.16 * edge + rand(i, 8) * 0.012;
        zone = yy > 0.48 ? 0 : yy < -0.42 ? 5 : 6;
      }
      samples.push({ x, y, z, zone, bias: 0.72 + rand(i, 9) * 0.56 });
    }
    return samples;
  }

  function samplesFromFaceGeometry(facePoints, count) {
    const positions = facePoints?.geometry?.attributes?.position?.array;
    if (!positions || positions.length < 3) return null;
    const total = Math.floor(positions.length / 3);
    const limit = Math.min(total, count);
    const stride = total / limit;
    const samples = [];
    for (let i = 0; i < limit; i += 1) {
      const index = Math.min(total - 1, Math.floor(i * stride)) * 3;
      const x = Number(positions[index]);
      const y = Number(positions[index + 1]);
      const z = Number(positions[index + 2]);
      if (![x, y, z].every(Number.isFinite)) continue;
      samples.push({
        x, y, z: z + 0.002,
        zone: y > 0.48 ? 0 : y > 0.20 ? 1 : y < -0.42 ? 5 : Math.abs(x) < 0.13 ? 4 : 6,
        bias: 0.72 + rand(i, 9) * 0.56
      });
    }
    return samples.length ? samples : null;
  }

  function buildFromSamples(THREE, input) {
    if (!THREE?.BufferGeometry || !THREE?.ShaderMaterial) throw new Error("THREE is required");
    const samples = Array.from(input || []).slice(0, MAX_POINTS);
    if (!samples.length) throw new Error("at least one valid stipple sample is required");
    const positions = new Float32Array(samples.length * 3);
    const phases = new Float32Array(samples.length);
    const thresholds = new Float32Array(samples.length);
    const zones = new Float32Array(samples.length);
    const biases = new Float32Array(samples.length);
    const depthRanks = new Float32Array(samples.length);
    const homeDepths = new Float32Array(samples.length);
    const velocities = new Float32Array(samples.length * 3);

    samples.forEach((sample, index) => {
      const x = Number(sample.x), y = Number(sample.y), z = Number(sample.z);
      if (![x, y, z].every(Number.isFinite)) throw new Error("sample coordinates must be finite");
      const j = index * 3;
      positions[j] = x; positions[j + 1] = y; positions[j + 2] = z;
      depthRanks[index] = clamp(0.5 + z * 0.5, 0.5, 0, 1);
      homeDepths[index] = z;
      phases[index] = rand(index, 17) * Math.PI * 2;
      thresholds[index] = rand(index, 19);
      zones[index] = clamp(sample.zone, 0, 0, 8);
      biases[index] = clamp(sample.bias, 1, 0.25, 1.5);
    });

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute("aPhase", new THREE.BufferAttribute(phases, 1));
    geometry.setAttribute("aThreshold", new THREE.BufferAttribute(thresholds, 1));
    geometry.setAttribute("aZone", new THREE.BufferAttribute(zones, 1));
    geometry.setAttribute("aBias", new THREE.BufferAttribute(biases, 1));
    geometry.setAttribute("aDepthRank", new THREE.BufferAttribute(depthRanks, 1));
    const idle = profiles().idle || IDLE_PROFILE;
    const pointSize = pointSizing();
    const material = new THREE.ShaderMaterial({
      uniforms: {
        uPointSizeBase: { value: clamp(pointSize.base, DEFAULT_POINT_SIZE.base, 0.1, 2.0) },
        uPointSizeBiasScale: { value: clamp(pointSize.bias_scale, DEFAULT_POINT_SIZE.bias_scale, 0.0, 1.0) },
        uPointSizeBiasMin: { value: clamp(pointSize.bias_min, DEFAULT_POINT_SIZE.bias_min, 0.0, 1.5) },
        uPointSizeBiasMax: { value: clamp(pointSize.bias_max, DEFAULT_POINT_SIZE.bias_max, 0.25, 1.5) },
        uPointSizeReferenceDepth: { value: clamp(pointSize.reference_depth, DEFAULT_POINT_SIZE.reference_depth, 1.0, 20.0) },
        uPointSizeDistanceMin: { value: clamp(pointSize.distance_min, DEFAULT_POINT_SIZE.distance_min, 0.1, 2.0) },
        uPointSizeDistanceMax: { value: clamp(pointSize.distance_max, DEFAULT_POINT_SIZE.distance_max, 0.1, 2.0) },
        uPointSizeOutputMin: { value: clamp(pointSize.output_min, DEFAULT_POINT_SIZE.output_min, 1.0, 1.5) },
        uPointSizeOutputMax: { value: clamp(pointSize.output_max, DEFAULT_POINT_SIZE.output_max, 1.0, 1.5) },
        uTime: { value: 0 }, uDensity: { value: idle.density },
        uRipple: { value: idle.ripple }, uTurbulence: { value: idle.turbulence },
        uLuminosity: { value: idle.luminosity }, uAttract: { value: idle.attract },
        uOpacity: { value: 0.74 }, uEntropy: { value: 0.18 },
        uMotionScale: { value: 1 },
        uColor: { value: new THREE.Color(0.90, 0.89, 0.86) }
      },
      vertexShader: `
        attribute float aPhase;
        attribute float aThreshold;
        attribute float aZone;
        attribute float aBias;
        attribute float aDepthRank;
        uniform float uTime;
        uniform float uDensity;
        uniform float uRipple;
        uniform float uTurbulence;
        uniform float uAttract;
        uniform float uEntropy;
        uniform float uMotionScale;
        uniform float uPointSizeBase;
        uniform float uPointSizeBiasScale;
        uniform float uPointSizeBiasMin;
        uniform float uPointSizeBiasMax;
        uniform float uPointSizeReferenceDepth;
        uniform float uPointSizeDistanceMin;
        uniform float uPointSizeDistanceMax;
        uniform float uPointSizeOutputMin;
        uniform float uPointSizeOutputMax;
        uniform float uLuminosity;
        varying float vAlpha;
        varying float vZone;
        varying float vThreshold;
        varying float vDepthRank;
        void main() {
          vec3 p = position;
          float zoneWeight = 0.72 + aZone * 0.035;
          float drift = sin(uTime * 0.72 + aPhase) * 0.008 * uTurbulence * uMotionScale;
          p.x += drift * (aZone < 2.0 ? 0.6 : 1.0);
          p.y += cos(uTime * 0.61 + aPhase * 1.17) * drift * 0.78;
          p.z += sin(length(position.xy) * 17.0 - uTime * 2.2 + aPhase) * uRipple * 0.013 * uMotionScale;
          p.xy *= 1.0 - uAttract * 0.007;
          vec4 mv = modelViewMatrix * vec4(p, 1.0);
          gl_Position = projectionMatrix * mv;
          // One point, one pixel: depth and bias belong in brightness (vAlpha
          // already folds zone weight, bias and luminosity), not in point size.
          // The face breathes: luminosity sways about five percent over ~11 s,
          // the pace of a resting breath, so the field is never perfectly
          // still while it waits. The breath rides brightness only — the same
          // seam the one-pixel law owns — and freezes twice over under reduced
          // motion: uTime stops and uMotionScale goes to 0.
          float breath = 1.0 + uMotionScale * 0.05 * sin(uTime * 0.5712);
          float distanceScale = clamp(uPointSizeReferenceDepth / max(1.0, -mv.z),
            uPointSizeDistanceMin, uPointSizeDistanceMax);
          gl_PointSize = 1.0;
          vThreshold = aThreshold;
          vDepthRank = aDepthRank;
          vAlpha = clamp((0.34 + zoneWeight * 0.56) * aBias * uLuminosity * breath * (1.0 - uEntropy * 0.08) * distanceScale, 0.0, 1.0);
          vZone = aZone;
        }
      `,
      fragmentShader: `
        uniform vec3 uColor;
        uniform float uOpacity;
        uniform float uDensity;
        varying float vAlpha;
        varying float vZone;
        varying float vThreshold;
        varying float vDepthRank;
        void main() {
          vec2 p = gl_PointCoord - vec2(0.5);
          if (vThreshold > uDensity || length(p) > 0.5) discard;
          float zoneTone = vZone < 2.0 ? 1.0 : (vZone > 5.0 ? 0.84 : 0.93);
          // One-pixel law: the shared depth rank affects brightness, never size.
          float depthTone = mix(0.68, 1.0, clamp(vDepthRank, 0.0, 1.0));
          gl_FragColor = vec4(uColor * zoneTone * depthTone, vAlpha * uOpacity);
        }
      `,
      transparent: true, depthWrite: false, depthTest: true
    });
    const points = new THREE.Points(geometry, material);
    points.name = "MASTER_FACE_STIPPLE";
    points.renderOrder = 8;
    points.frustumCulled = false;
    return {
      points, geometry, material, count: samples.length, root: null,
      swarm: { velocities, homePositions: positions.slice(), homeDepths, lastTime: null }
    };
  }

  function createDefault(THREE, count) {
    return buildFromSamples(THREE, defaultSamples(pointBudget(count)));
  }

  function profileFor(state) {
    const mode = String(state?.mode || state?.mood || "idle").toLowerCase();
    const table = profiles();
    return table[mode] || table.idle || IDLE_PROFILE;
  }

  function configure(values = {}) {
    for (const key of ["density", "ripple", "turbulence", "luminosity", "attract", "opacity"]) {
      if (values[key] !== undefined) overrides[key] = clamp(values[key], overrides[key] ?? 0.5, 0, key === "luminosity" ? 1.2 : 1);
    }
    window.dispatchEvent(new CustomEvent("master:stipple-configured", { detail: { ...overrides } }));
    return { ...overrides };
  }

  function syncFromFaceState(system, state) {
    if (!system?.material || !state) return;
    const profile = { ...profileFor(state), ...overrides };
    // Missing telemetry is not zero pressure. Keep the canonical profile unchanged
    // until a pressure reading exists; face events report pct on a 0..100 scale,
    // while normalized 0..1 values remain accepted for compatibility.
    const pressureValue = state.pressureFields?.pct;
    const pressureRaw = pressureValue == null ? null : Number(pressureValue);
    const pressure = pressureRaw == null || !Number.isFinite(pressureRaw)
      ? 0.5
      : pressureRaw > 1
        ? clamp(pressureRaw / 100, 0, 0, 1)
        : clamp(pressureRaw, 0, 0, 1);
    const entropy = clamp(state.pressureFields?.entropy ?? state.entropy ?? 0.18, 0.18, 0, 1);
    const motion = reducedMotionEnabled(state) ? 0 : 1;
    const u = system.material.uniforms;
    u.uDensity.value = clamp(profile.density + (pressure - 0.5) * 0.24, profile.density, 0.08, 0.98);
    u.uRipple.value = clamp(profile.ripple, 0, 0, 1) * motion;
    u.uTurbulence.value = clamp(profile.turbulence + entropy * 0.18, 0, 0, 1) * motion;
    u.uLuminosity.value = clamp(profile.luminosity, 0.76, 0.2, 1.2);
    u.uAttract.value = clamp(profile.attract, 0, 0, 1);
    u.uEntropy.value = entropy;
    u.uMotionScale.value = motion;
    u.uOpacity.value = clamp(overrides.opacity, 0.74, 0.1, 1);
    if (swarmConfiguration().enabled === true) {
      // The particle material is pure white; visual identity does not inherit mood palettes.
      u.uColor.value.setRGB(1, 1, 1);
    } else {
      const cs = getComputedStyle(document.body);
      const rgb = ["--mood-r", "--mood-g", "--mood-b"].map((key) => Number.parseFloat(cs.getPropertyValue(key)));
      if (rgb.every(Number.isFinite)) u.uColor.value.setRGB(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255);
    }
  }

  function swarmConfiguration() {
    return window.MASTER_FACE_CONTRACT?.swarm || {};
  }

  function canonicalSwarmMode(state = {}) {
    const mode = String(state.mode || state.mood || "idle").toLowerCase();
    if (mode === "thinking") return "thinking";
    if (["attentive", "listening", "working", "speaking", "ready"].includes(mode)) return "attentive";
    return "idle";
  }

  function modeMultipliersFor(state = {}) {
    const modes = swarmConfiguration().mode_multipliers || {};
    return modes[canonicalSwarmMode(state)] || modes.idle || { eyes: 1, core: 1, noise: 0 };
  }

  function glyphForDepth(rank) {
    const ramp = swarmConfiguration().glyph_ramp;
    if (!Array.isArray(ramp) || !ramp.length) return "•";
    const value = clamp(rank, 0.5, 0, 1);
    return ramp[Math.floor(value * (ramp.length - 1) + 0.5)];
  }

  // CPU integration mirrors Master::Face::Swarm. Snapshot positions before
  // neighbor forces so a particle's result never depends on iteration order.
  function updateSwarm(system, state = {}, dt = 1 / 60, timeSeconds = 0) {
    const config = swarmConfiguration();
    if (config.enabled !== true || reducedMotionEnabled(state) || !system?.swarm) return false;
    const field = config.target_field;
    const attribute = system.geometry?.attributes?.position;
    const depthAttribute = system.geometry?.attributes?.aDepthRank;
    if (!field?.head || !field?.eyes || !field?.mouth || !attribute?.array || !depthAttribute?.array) return false;
    const delta = clamp(dt, 0, 0, 0.05);
    if (!(delta > 0)) return false;

    const positions = attribute.array;
    const source = positions.slice();
    const velocities = system.swarm.velocities;
    const forces = new Float32Array(source.length);
    const head = field.head;
    const center = head.center.map(Number);
    const scale = head.scale.map((value) => Math.max(0.001, Math.abs(Number(value))));
    const softness = Math.max(0.001, Number(field.softness) || 0.72);
    const multipliers = modeMultipliersFor(state);
    const noise = Math.max(0, Number(config.noise_scale) || 0) * (Number(multipliers.noise) || 0);
    const cohesionRadius = Math.max(0, Number(config.cohesion_radius) || 0);
    const separationRadius = Math.max(0, Number(config.separation_radius) || 0);
    const cohesionSquared = cohesionRadius * cohesionRadius;
    const separationSquared = separationRadius * separationRadius;
    const eyes = Object.values(field.eyes);
    const count = Math.floor(source.length / 3);
    const push = (offset, x, y, z) => {
      forces[offset] += x;
      forces[offset + 1] += y;
      forces[offset + 2] += z;
    };

    for (let i = 0; i < count; i += 1) {
      const offset = i * 3;
      const x = source[offset], y = source[offset + 1], z = source[offset + 2];
      const dx = (center[0] - x) / scale[0];
      const dy = (center[1] - y) / scale[1];
      const dz = (center[2] - z) / scale[2];
      const dist = Math.sqrt(dx * dx + dy * dy + dz * dz) + 1e-5;
      const falloff = Math.exp(-(dist * dist) / softness);
      const coreWeight = Number(head.weight ?? 1) * Number(multipliers.core ?? 1);
      push(offset, coreWeight * falloff * (center[0] - x), coreWeight * falloff * (center[1] - y), coreWeight * falloff * (center[2] - z));

      for (const eye of eyes) {
        const point = eye.pos;
        const ex = Number(point[0]) - x, ey = Number(point[1]) - y, ez = Number(point[2]) - z;
        const d = Math.sqrt(ex * ex + ey * ey + ez * ez) + 1e-5;
        const radius = Math.max(0.001, Number(eye.radius) || 0.17);
        const factor = Number(eye.weight ?? 1) * Number(multipliers.eyes ?? 1) * Math.exp(-Math.pow(d / radius, 2));
        push(offset, factor * ex, factor * ey, factor * ez);
      }

      const mouth = field.mouth;
      const mx = Number(mouth.pos[0]) - x, my = Number(mouth.pos[1]) - y, mz = Number(mouth.pos[2]) - z;
      const mouthDistance = Math.sqrt(mx * mx + my * my + mz * mz) + 1e-5;
      const mouthRadius = Math.max(0.001, Number(mouth.radius) || 0.34);
      const mouthFactor = Number(mouth.weight ?? 1) * Math.exp(-Math.pow(mouthDistance / mouthRadius, 2));
      push(offset, mouthFactor * mx, mouthFactor * my, mouthFactor * mz);

      let cohesionX = 0, cohesionY = 0, cohesionZ = 0, neighbors = 0;
      for (let j = 0; j < count; j += 1) {
        if (i === j) continue;
        const jOffset = j * 3;
        const ox = source[jOffset] - x, oy = source[jOffset + 1] - y, oz = source[jOffset + 2] - z;
        const distanceSquared = ox * ox + oy * oy + oz * oz;
        if (cohesionSquared > 0 && distanceSquared < cohesionSquared) {
          cohesionX += ox; cohesionY += oy; cohesionZ += oz; neighbors += 1;
        }
        if (separationSquared > 0 && distanceSquared > 1e-8 && distanceSquared < separationSquared) {
          const distance = Math.sqrt(distanceSquared);
          const factor = (Number(config.separation_strength) || 0) * (1 - distance / separationRadius) / distance;
          push(offset, -ox * factor, -oy * factor, -oz * factor);
        }
      }
      if (neighbors > 0) {
        const factor = (Number(config.cohesion_strength) || 0) / neighbors;
        push(offset, cohesionX * factor, cohesionY * factor, cohesionZ * factor);
      }
      const phase = (i + 1) * 12.9898 + (Number(timeSeconds) || 0) * 1.71;
      push(offset, Math.sin(phase) * noise * 0.5, Math.sin(phase * 1.31) * noise * 0.5, Math.cos(phase * 0.73) * noise * 0.5);
    }

    const damping = clamp(config.damping, 0.86, 0, 1);
    const low = center.map((value, index) => value - scale[index] * 1.25);
    const high = center.map((value, index) => value + scale[index] * 1.25);
    for (let i = 0; i < count; i += 1) {
      const offset = i * 3;
      for (let axis = 0; axis < 3; axis += 1) {
        velocities[offset + axis] = (velocities[offset + axis] + forces[offset + axis] * delta) * damping;
        positions[offset + axis] = Math.max(low[axis], Math.min(high[axis], source[offset + axis] + velocities[offset + axis]));
      }
      depthAttribute.array[i] = clamp(0.5 + positions[offset + 2] * 0.5, 0.5, 0, 1);
    }
    attribute.needsUpdate = true;
    depthAttribute.needsUpdate = true;
    return true;
  }

  function tick(system, state, timeSeconds) {
    if (!system?.material) return;
    const time = Number(timeSeconds) || 0;
    const previous = system.swarm?.lastTime;
    const delta = previous == null ? 1 / 60 : clamp(time - previous, 0, 0, 0.05);
    if (system.swarm) system.swarm.lastTime = time;
    system.material.uniforms.uTime.value = reducedMotionEnabled(state) ? 0 : time;
    updateSwarm(system, state, delta, time);
    syncFromFaceState(system, state);
  }

  // Three.js scene roots may be Group, Object3D, or another container. Detect
  // the face by its point child, not an exact parent type label.
  function hasFacePoints(node) {
    return Array.isArray(node?.children) && node.children.some((child) =>
      child?.isPoints === true || child?.type === "Points"
    );
  }

  function isFaceScene(scene) {
    return Array.isArray(scene?.children) && scene.children.some(hasFacePoints);
  }

  async function install() {
    if (!enabled || wrappedRenderer || installing) return;
    const face = window.MASTER_FACE;
    const renderer = face?.renderer;
    const modulePath = window.MASTER_ASSET_PATHS?.threeModule;
    if (!renderer || typeof renderer.render !== "function" || !modulePath) return;
    let THREE;
    installing = true;
    try {
      THREE = await import(new URL(modulePath, document.baseURI).href);
    } catch (error) {
      window.MASTER_LOG?.warn?.("face_stipple:three_import_failed", error);
      return;
    } finally {
      installing = false;
    }
    if (wrappedRenderer || window.MASTER_FACE?.renderer !== renderer) return;

    const previousRender = renderer.render;
    originalRender = previousRender;
    wrappedRenderer = renderer;
    rendererCanvas = renderer.domElement || null;
    rendererCanvas?.addEventListener?.("webglcontextlost", onContextLost, false);
    rendererCanvas?.addEventListener?.("webglcontextrestored", onContextRestored, false);
    document.addEventListener?.("visibilitychange", onVisibilityChange, false);
    renderWrapper = function(scene, camera, ...rest) {
      const now = performance.now();
      if (lastFrameAt > 0) {
        lastRenderIntervalMs = Math.max(0, now - lastFrameAt);
        if (lastRenderIntervalMs > 0) {
          frameIntervals.push(lastRenderIntervalMs);
          if (frameIntervals.length > FRAME_SAMPLE_LIMIT) frameIntervals.shift();
        }
      }
      lastFrameAt = now;
      renderedFrames += 1;
      if (active?.points) active.points.visible = !document.hidden && contextState !== "lost";
      if (!active && isFaceScene(scene)) {
        const root = scene.children.find(hasFacePoints);
        const facePoints = root?.children?.find((child) => child?.type === "Points");
        const sampled = samplesFromFaceGeometry(facePoints, pointBudget());
        active = buildFromSamples(THREE, sampled || defaultSamples(pointBudget()));
        active.root = root || scene;
        active.root.add(active.points);
        window.__MASTER_STIPPLE__ = active;
      }
      if (active && (active.root === scene || active.root?.parent === scene)) {
        tick(active, currentFaceState(), performance.now() * 0.001);
      }
      return previousRender.call(this, scene, camera, ...rest);
    };
    renderer.render = renderWrapper;
  }

  function onContextLost(event) {
    // Context restoration is browser-controlled; cancellation asks the browser
    // to attempt restoration instead of treating this layer as permanently lost.
    event?.preventDefault?.();
    contextState = "lost";
    if (active?.points) active.points.visible = false;
    window.dispatchEvent?.(new CustomEvent("master:stipple-context", { detail: { state: "lost" } }));
  }

  function onContextRestored() {
    contextState = "ready";
    if (active?.points) active.points.visible = !document.hidden;
    window.dispatchEvent?.(new CustomEvent("master:stipple-context", { detail: { state: "restored" } }));
  }

  function onVisibilityChange() {
    if (active?.points) active.points.visible = !document.hidden && contextState !== "lost";
  }

  function uninstall() {
    const wasInstalled = Boolean(wrappedRenderer);
    if (wrappedRenderer && renderWrapper && wrappedRenderer.render === renderWrapper && originalRender) {
      wrappedRenderer.render = originalRender;
    }
    rendererCanvas?.removeEventListener?.("webglcontextlost", onContextLost, false);
    rendererCanvas?.removeEventListener?.("webglcontextrestored", onContextRestored, false);
    document.removeEventListener?.("visibilitychange", onVisibilityChange, false);
    if (active?.root && active.points) active.root.remove?.(active.points);
    active?.geometry?.dispose?.();
    active?.material?.dispose?.();
    if (window.__MASTER_STIPPLE__ === active) delete window.__MASTER_STIPPLE__;
    active = null;
    wrappedRenderer = null;
    originalRender = null;
    renderWrapper = null;
    rendererCanvas = null;
    renderedFrames = 0;
    lastFrameAt = 0;
    lastRenderIntervalMs = null;
    frameIntervals.length = 0;
    contextState = "ready";
    return wasInstalled;
  }

  function snapshot() {
    const state = currentFaceState();
    const uniforms = active?.material?.uniforms || {};
    const intervals = frameIntervals.filter((value) => Number.isFinite(value) && value > 0).sort((a, b) => a - b);
    const percentile = (fraction) => {
      if (!intervals.length) return null;
      const index = Math.min(intervals.length - 1, Math.max(0, Math.ceil(fraction * intervals.length) - 1));
      return Number(intervals[index].toFixed(2));
    };
    const meanInterval = intervals.length
      ? Number((intervals.reduce((sum, value) => sum + value, 0) / intervals.length).toFixed(2))
      : null;
    const value = (name) => {
      const raw = uniforms[name]?.value;
      return Number.isFinite(Number(raw)) ? Number(raw) : null;
    };
    return {
      enabled,
      swarmEnabled: swarmConfiguration().enabled === true,
      swarmMode: canonicalSwarmMode(state),
      installing,
      installed: Boolean(wrappedRenderer && renderWrapper && wrappedRenderer.render === renderWrapper),
      visible: Boolean(active?.points?.visible && !document.hidden && contextState !== "lost"),
      hidden: Boolean(document.hidden),
      context: contextState,
      reducedMotion: reducedMotionEnabled(state),
      mode: String(state.mode || state.mood || "idle").toLowerCase(),
      pointCount: Number(active?.count) || 0,
      pointCeiling: pointBudget(),
      rendererCalls: renderedFrames,
      lastRenderIntervalMs,
      renderTiming: {
        sampleCount: intervals.length,
        meanRenderIntervalMs: meanInterval,
        p50RenderIntervalMs: percentile(0.50),
        p95RenderIntervalMs: percentile(0.95),
        approximateRenderCallsPerSecond: lastRenderIntervalMs > 0
          ? Number((1000 / lastRenderIntervalMs).toFixed(1)) : null
      },
      uniforms: {
        density: value("uDensity"), ripple: value("uRipple"), turbulence: value("uTurbulence"),
        luminosity: value("uLuminosity"), attract: value("uAttract"), opacity: value("uOpacity"),
        time: value("uTime"),
        pointSizeBase: value("uPointSizeBase"),
        pointSizeBiasScale: value("uPointSizeBiasScale"),
        pointSizeReferenceDepth: value("uPointSizeReferenceDepth"),
        pointSizeDistanceMin: value("uPointSizeDistanceMin"),
        pointSizeDistanceMax: value("uPointSizeDistanceMax"),
        pointSizeOutputMin: value("uPointSizeOutputMin"),
        pointSizeOutputMax: value("uPointSizeOutputMax")
      }
    };
  }

  function mount(scene, THREE, state, count) {
    if (!scene || !THREE) return null;
    const system = createDefault(THREE, count);
    scene.add(system.points);
    tick(system, state || {}, performance.now() * 0.001);
    return system;
  }

  function applyPalette(system, palette = {}) {
    const color = String(palette.accent || palette.color || "").trim();
    if (!color || !system?.material?.uniforms?.uColor) return false;
    system.material.uniforms.uColor.value.set(color);
    return true;
  }

  window.MASTER_FACE_STIPPLE = Object.freeze({
    createDefault, buildFromSamples, mount, configure, syncFromFaceState, tick, updateSwarm,
    glyphForDepth, pointBudget, canonicalSwarmMode, modeMultipliersFor, applyPalette,
    get profiles() { return profiles(); },
    get system() { return active; },
    get enabled() { return enabled; },
    install, uninstall, snapshot, isFaceScene
  });

  window.addEventListener("master:face-ready", install);
  if (document.body?.classList.contains("face-ready") || window.MASTER_FACE?.renderer) install();
})();
