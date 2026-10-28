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
    const cs = getComputedStyle(document.body);
    const rgb = ["--mood-r", "--mood-g", "--mood-b"].map((key) => Number.parseFloat(cs.getPropertyValue(key)));
    if (rgb.every(Number.isFinite)) u.uColor.value.setRGB(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255);
  }

  function tick(system, state, timeSeconds) {
    if (!system?.material) return;
    system.material.uniforms.uTime.value = reducedMotionEnabled(state) ? 0 : Number(timeSeconds) || 0;
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
    createDefault, buildFromSamples, mount, configure, syncFromFaceState, tick, applyPalette,
    get profiles() { return profiles(); },
    get system() { return active; },
    get enabled() { return enabled; },
    install, uninstall, snapshot, isFaceScene
  });

  window.addEventListener("master:face-ready", install);
  if (document.body?.classList.contains("face-ready") || window.MASTER_FACE?.renderer) install();
})();
