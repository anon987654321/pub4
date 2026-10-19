/* Additive, bounded stipple layer for the existing MASTER face.
 * It reuses the live face state and face geometry where possible. ParticleKernel,
 * the original point cloud and its render loop remain untouched.
 */
(() => {
  "use strict";

  const params = new URLSearchParams(window.location.search || "");
  const enabled = params.get("stipple") !== "0";
  const MAX_POINTS = 14_000;
  const MOBILE_FALLBACK = 420;
  const DESKTOP_FALLBACK = 1_200;
  // The nine moods live in MASTER/data/tokens.yml (face_interface.stipple.profiles) and arrive
  // as MASTER_FACE_CONTRACT; only idle is kept here so a page without the contract still draws.
  const IDLE_PROFILE = Object.freeze({ density: 0.44, ripple: 0.03, turbulence: 0.04, luminosity: 0.76, attract: 0.14 });
  const profiles = () => window.MASTER_FACE_CONTRACT?.stipple?.profiles || {};

  const overrides = {};
  let wrappedRenderer = null;
  let active = null;

  const clamp = (value, fallback, min = 0, max = 1) => {
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(min, Math.min(max, number)) : fallback;
  };
  const rand = (index, salt = 0) => {
    const value = Math.sin(index * 12.9898 + salt * 78.233) * 43758.5453;
    return value - Math.floor(value);
  };

  function pointBudget(requested) {
    const contract = window.MASTER_FACE_CONTRACT || {};
    const budget = contract.spatial?.budget || {};
    const mobile = matchMedia("(pointer: coarse)").matches;
    const configured = Number(mobile ? budget.mobile_points : budget.desktop_points);
    const fallback = mobile ? MOBILE_FALLBACK : DESKTOP_FALLBACK;
    const ceiling = Number.isFinite(configured) && configured > 0
      ? Math.min(MAX_POINTS, Math.floor(configured))
      : fallback;
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

    samples.forEach((sample, index) => {
      const x = Number(sample.x), y = Number(sample.y), z = Number(sample.z);
      if (![x, y, z].every(Number.isFinite)) throw new Error("sample coordinates must be finite");
      const j = index * 3;
      positions[j] = x; positions[j + 1] = y; positions[j + 2] = z;
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
    const idle = profiles().idle || IDLE_PROFILE;
    const material = new THREE.ShaderMaterial({
      uniforms: {
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
        uniform float uTime;
        uniform float uDensity;
        uniform float uRipple;
        uniform float uTurbulence;
        uniform float uAttract;
        uniform float uEntropy;
        uniform float uMotionScale;
        uniform float uLuminosity;
        varying float vAlpha;
        varying float vZone;
        varying float vThreshold;
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
          gl_PointSize = 1.0;
          vThreshold = aThreshold;
          vAlpha = clamp((0.34 + zoneWeight * 0.56) * aBias * uLuminosity * (1.0 - uEntropy * 0.08), 0.0, 1.0);
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
        void main() {
          vec2 p = gl_PointCoord - vec2(0.5);
          if (vThreshold > uDensity || length(p) > 0.5) discard;
          float tone = vZone < 2.0 ? 1.0 : (vZone > 5.0 ? 0.84 : 0.93);
          gl_FragColor = vec4(uColor * tone, vAlpha * uOpacity);
        }
      `,
      transparent: true, depthWrite: false, depthTest: true
    });
    const points = new THREE.Points(geometry, material);
    points.name = "MASTER_FACE_STIPPLE";
    points.renderOrder = 8;
    points.frustumCulled = false;
    return { points, geometry, material, count: samples.length, root: null };
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
    const pressureRaw = Number(state.pressureFields?.pct ?? 0);
    const pressure = pressureRaw > 1 ? clamp(pressureRaw / 100, 0, 0, 1) : clamp(pressureRaw, 0, 0, 1);
    const entropy = clamp(state.pressureFields?.entropy ?? state.entropy ?? 0.18, 0.18, 0, 1);
    const motion = state.reducedMotion ? 0 : 1;
    const u = system.material.uniforms;
    u.uDensity.value = clamp(profile.density + (pressure - 0.5) * 0.24, profile.density, 0.08, 0.98);
    u.uRipple.value = clamp(profile.ripple, 0, 0, 1) * motion;
    u.uTurbulence.value = clamp(profile.turbulence + entropy * 0.18, 0, 0, 1) * motion;
    u.uLuminosity.value = clamp(profile.luminosity, 0.76, 0.2, 1.2);
    u.uAttract.value = clamp(profile.attract, 0, 0, 1);
    u.uEntropy.value = entropy;
    u.uMotionScale.value = motion;
    u.uOpacity.value = clamp(overrides.opacity, 0.74, 0.1, 1);
    const cs = getComputedStyle(document.body);
    const rgb = ["--mood-r", "--mood-g", "--mood-b"].map((key) => Number.parseFloat(cs.getPropertyValue(key)));
    if (rgb.every(Number.isFinite)) u.uColor.value.setRGB(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255);
  }

  function tick(system, state, timeSeconds) {
    if (!system?.material) return;
    system.material.uniforms.uTime.value = state?.reducedMotion ? 0 : Number(timeSeconds) || 0;
    syncFromFaceState(system, state);
  }

  function isFaceScene(scene) {
    return Array.isArray(scene?.children) && scene.children.some((node) =>
      node?.type === "Object3D" && node.children?.some((child) => child?.type === "Points")
    );
  }

  async function install() {
    if (!enabled || wrappedRenderer) return;
    const face = window.MASTER_FACE;
    const renderer = face?.renderer;
    const modulePath = window.MASTER_ASSET_PATHS?.threeModule;
    if (!renderer || typeof renderer.render !== "function" || !modulePath) return;
    let THREE;
    try {
      THREE = await import(new URL(modulePath, document.baseURI).href);
    } catch (error) {
      window.MASTER_LOG?.warn?.("face_stipple:three_import_failed", error);
      return;
    }
    if (wrappedRenderer || !window.MASTER_FACE?.renderer) return;

    const originalRender = renderer.render;
    wrappedRenderer = renderer;
    renderer.render = function(scene, camera, ...rest) {
      if (!active && isFaceScene(scene)) {
        const root = scene.children.find((node) => node?.type === "Object3D" &&
          node.children?.some((child) => child?.type === "Points"));
        const facePoints = root?.children?.find((child) => child?.type === "Points");
        const sampled = samplesFromFaceGeometry(facePoints, pointBudget());
        active = buildFromSamples(THREE, sampled || defaultSamples(pointBudget()));
        active.root = root || scene;
        active.root.add(active.points);
        window.__MASTER_STIPPLE__ = active;
      }
      if (active && (active.root === scene || active.root?.parent === scene)) {
        tick(active, window.MASTER_FACE?.State || {}, performance.now() * 0.001);
      }
      return originalRender.call(this, scene, camera, ...rest);
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
    createDefault, buildFromSamples, mount, configure, syncFromFaceState, tick, applyPalette,
    get profiles() { return profiles(); },
    get system() { return active; },
    get enabled() { return enabled; },
    install
  });

  window.addEventListener("master:face-ready", install);
  if (document.body?.classList.contains("face-ready") || window.MASTER_FACE?.renderer) install();
})();
