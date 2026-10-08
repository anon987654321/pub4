// MASTER FaceWorld: the browser's spatial projection of the same state the CLI exposes.
// It deliberately reuses the canonical face scene/camera/frame. There is no second
// WebGL renderer and no second animation loop.
(() => {
  "use strict";

  let THREE = null;
  let world = null;
  let shell = null;
  let shellMaterial = null;
  let splatProxy = null;
  let nodes = [];
  let edges = null;
  let pulses = [];
  let audio = { bass: 0, mid: 0, high: 0, onset: 0, rms: 0 };
  window.addEventListener("audio:update", (event) => {
    audio = { ...audio, ...(event.detail || {}) };
  }, { passive: true });
  let hudSprites = [];
  let splatCount = 0;
  let layers = {};
  let camera = null;
  let ready = false;
  let updating = false;

  const CONTRACT = window.MASTER_FACE_CONTRACT || {};
  const SPATIAL = CONTRACT.spatial || {};
  const NODE_LAYOUT = Object.entries(SPATIAL.nodes || {
    lib: [-1.38, 0.10, -0.28],
    law: [-0.70, 1.18, -0.10],
    tools: [1.40, 0.05, -0.20],
    web: [0.70, -1.10, -0.12],
    openbsd: [-0.82, -1.05, -0.16]
  }).map(([name, position]) => [name, ...position]);
  const LINK_LAYOUT = Array.isArray(SPATIAL.links) ? SPATIAL.links : [
    ["lib", "law"], ["law", "tools"], ["tools", "web"], ["web", "openbsd"], ["openbsd", "lib"],
    ["lib", "tools"], ["law", "web"], ["tools", "openbsd"], ["web", "lib"], ["openbsd", "law"]
  ];

  const TOPOLOGY_PROFILES = Object.freeze(SPATIAL.topology_profiles || {});
  const CAMERA = SPATIAL.camera || {};
  const BUDGET = SPATIAL.budget || {};
  const LAYER_NAMES = Array.isArray(SPATIAL.layers)
    ? SPATIAL.layers.map((name) => String(name))
    : ["identity", "eyes", "mouth", "cognition", "repository", "event_field", "camera", "hud"];

  function finite(value, fallback) {
    const number = Number(value);
    return Number.isFinite(number) ? number : fallback;
  }

  function colorFromCss() {
    const raw = getComputedStyle(document.documentElement)
      .getPropertyValue("--c-accent")
      .trim();

    try {
      return new THREE.Color(raw || "#d8d6e0");
    } catch (_error) {
      return new THREE.Color("#d8d6e0");
    }
  }

  function seeded(index, salt = 0) {
    const x = Math.sin(index * 12.9898 + salt * 78.233) * 43758.5453;
    return x - Math.floor(x);
  }

  function makeShell() {
    const shellSpec = SPATIAL.shell || {};
    const geometry = new THREE.SphereGeometry(
      finite(shellSpec.radius, 1.58),
      finite(shellSpec.width_segments, 28),
      finite(shellSpec.height_segments, 20)
    );
    shellMaterial = new THREE.ShaderMaterial({
      uniforms: {
        uTime: { value: 0 },
        uTension: { value: 0.24 },
        uPulse: { value: 0.12 },
        uFracture: { value: 0 },
        uOpacity: { value: 0.12 },
        uEntropy: { value: 0.18 },
        uColor: { value: colorFromCss() }
      },
      vertexShader: [
        "uniform float uTime;",
        "uniform float uTension;",
        "varying vec3 vNormal;",
        "varying vec3 vPosition;",
        "void main() {",
        "  vNormal = normalize(normalMatrix * normal);",
        "  vPosition = position;",
        "  vec3 p = position;",
        "  float ny = clamp(p.y / 1.58, -1.0, 1.0);",
        "  float jawTaper = smoothstep(-0.98, -0.16, ny);",
        "  float cheekFull = 1.0 - smoothstep(0.02, 0.78, abs(ny));",
        "  p.x *= mix(0.72, 0.95, jawTaper);",
        "  p.x *= 1.0 + cheekFull * 0.08;",
        "  p.y *= 1.04;",
        "  p.z *= 0.72;",
        "  p.z += cheekFull * 0.045;",
        "  float ripple = sin(p.y * 7.0 + uTime * 0.00055) * sin(p.x * 5.0 - uTime * 0.00031);",
        "  float pressure = 0.014 + uPulse * 0.008 + uFracture * 0.020;",
        "  p += normal * ripple * pressure * (0.25 + uTension);",
        "  p += normal * sin(p.x * 23.0 + p.y * 17.0 + uTime * 0.0011) * uFracture * 0.012;",
        "  gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);",
        "}"
      ].join("\n"),
      fragmentShader: [
        "uniform float uTime;",
        "uniform float uPulse;",
        "uniform float uFracture;",
        "uniform float uOpacity;",
        "uniform float uEntropy;",
        "uniform vec3 uColor;",
        "varying vec3 vNormal;",
        "varying vec3 vPosition;",
        "void main() {",
        "  float latitude = smoothstep(0.985, 1.0, abs(vNormal.z));",
        "  float contour = smoothstep(0.95, 0.995, abs(sin(vPosition.y * 10.0 + vPosition.x * 4.0)));",
        "  float brow = smoothstep(0.965, 0.995, abs(sin(vPosition.y * 8.0 + 0.9)) * (0.78 + 0.22 * abs(vPosition.x)));",
        "  float jaw = smoothstep(0.972, 0.997, abs(sin(vPosition.y * 15.0 - vPosition.x * 3.0)));",
        "  float crack = smoothstep(0.80, 0.98, abs(sin(vPosition.z * 31.0 + vPosition.y * 17.0 + uTime * 0.0013))) * uFracture;",
        "  contour = max(contour, max(brow * 0.72, jaw * 0.54));",
        "  float alpha = max(contour * uOpacity + latitude * uOpacity * 0.30, crack * uOpacity * 0.86);",
        "  alpha *= 0.65 + uEntropy * 0.35 + uPulse * 0.12;",
        "  if (alpha < 0.012) discard;",
        "  gl_FragColor = vec4(uColor, alpha);",
        "}"
      ].join("\n"),
      transparent: true,
      depthWrite: false,
      depthTest: true,
      side: THREE.DoubleSide
    });

    shell = new THREE.Mesh(geometry, shellMaterial);
    shell.name = "master-sdf-shell";
    shell.renderOrder = -2;
    (layers.identity || world).add(shell);
  }

  function makeNodes() {
    const geometry = new THREE.SphereGeometry(0.034, 8, 6);
    nodes = NODE_LAYOUT.map(([name, x, y, z], index) => {
      const material = new THREE.MeshBasicMaterial({
        color: colorFromCss(),
        transparent: true,
        opacity: 0.58,
        depthWrite: false
      });
      const node = new THREE.Mesh(geometry, material);
      node.name = `master-node-${name}`;
      node.position.set(x, y, z);
      node.userData.phase = seeded(index, 19) * Math.PI * 2;
      node.userData.index = index;
      (layers.repository || world).add(node);
      return node;
    });

    const positions = [];
    const indexByName = Object.fromEntries(NODE_LAYOUT.map(([name], index) => [name, index]));
    const links = LINK_LAYOUT.map(([a, b]) => [indexByName[a], indexByName[b]])
      .filter(([a, b]) => Number.isInteger(a) && Number.isInteger(b));

    links.forEach(([a, b]) => {
      positions.push(...nodes[a].position.toArray(), ...nodes[b].position.toArray());
    });

    const edgeGeometry = new THREE.BufferGeometry();
    edgeGeometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
    edges = new THREE.LineSegments(
      edgeGeometry,
      new THREE.LineBasicMaterial({
        color: colorFromCss(),
        transparent: true,
        opacity: 0.10,
        depthWrite: false
      })
    );
    edges.name = "master-semantic-edges";
    edges.renderOrder = -1;
    (layers.repository || world).add(edges);
  }

  function makeSplatProxy() {
    const count = Math.max(384, Math.min(Number(BUDGET.desktop_points) || 1200, 1200));
    splatCount = count;
    const positions = new Float32Array(count * 3);
    const sizes = new Float32Array(count);
    for (let i = 0; i < count; i += 1) {
      const a = seeded(i, 2.1) * Math.PI * 2;
      const b = Math.acos(2 * seeded(i, 3.1) - 1);
      const radius = 1.55 + seeded(i, 4.1) * 0.18;
      positions[i * 3] = Math.sin(b) * Math.cos(a) * radius;
      positions[i * 3 + 1] = Math.cos(b) * radius;
      positions[i * 3 + 2] = Math.sin(b) * Math.sin(a) * radius;
      sizes[i] = 0.012 + seeded(i, 5.1) * 0.018;
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute("size", new THREE.BufferAttribute(sizes, 1));

    splatProxy = new THREE.Points(
      geometry,
      new THREE.PointsMaterial({
        color: colorFromCss(),
        size: 0.018,
        transparent: true,
        opacity: 0.085,
        depthWrite: false,
        sizeAttenuation: true
      })
    );
    splatProxy.name = "master-splat-field";
    splatProxy.renderOrder = -1;
    (layers.cognition || world).add(splatProxy);

    document.documentElement.dataset.faceSplatMode =
      typeof THREE.GaussianSplat === "function" ? "native-capable-proxy" : "deterministic-points";
  }

  function makeHud() {
    const host = layers.hud || world;
    const limit = Math.max(0, Math.min(NODE_LAYOUT.length, Number(BUDGET.hud_labels) || 5));
    if (!host || !THREE || hudSprites.length || limit === 0) return;

    NODE_LAYOUT.slice(0, limit).forEach(([name, x, y, z]) => {
      const canvas = document.createElement("canvas");
      canvas.width = 320;
      canvas.height = 48;
      const context = canvas.getContext("2d");
      if (!context) return;
      context.clearRect(0, 0, canvas.width, canvas.height);
      context.font = "18px monospace";
      context.textBaseline = "middle";
      context.fillStyle = "#ffffff";
      context.fillText(name + "0", 8, 24);

      const texture = new THREE.CanvasTexture(canvas);
      texture.generateMipmaps = false;
      texture.minFilter = THREE.NearestFilter;
      texture.magFilter = THREE.NearestFilter;

      const material = new THREE.SpriteMaterial({
        map: texture,
        transparent: true,
        opacity: 0,
        depthTest: false,
        depthWrite: false
      });
      const sprite = new THREE.Sprite(material);
      sprite.name = "master-hud-" + name;
      sprite.scale.set(0.72, 0.108, 1);
      sprite.position.set(x, y, z + 0.12);
      host.add(sprite);
      hudSprites.push({ name, nodeName: "master-node-" + name, sprite });
    });
  }

  function boot() {
    if (ready || !window.MASTER_FACE?.scene) return;

    const scene = window.MASTER_FACE.scene;
    world = new THREE.Group();
    world.name = "master-face-world";
    camera = window.MASTER_FACE.camera || null;

    for (const name of LAYER_NAMES) {
      const group = new THREE.Group();
      group.name = `master-face-layer-${name}`;
      layers[name] = group;
      world.add(group);
    }

    const host = window.MASTER_FACE.head || scene;
    host.add(world);

    makeShell();
    makeNodes();
    makeSplatProxy();
    makeHud();

    const budget = window.MASTER_FACE_STATE?.renderBudget?.() || {};
    const initialDpr = Math.min(Number(budget.dpr || 1), Number(BUDGET.max_device_pixel_ratio || 2));
    document.documentElement.style.setProperty("--master-face-points", String(Math.min(
      Number(budget.points || 420),
      Number(BUDGET.desktop_points || 1200)
    )));
    if (window.MASTER_FACE?.renderer?.setPixelRatio) window.MASTER_FACE.renderer.setPixelRatio(initialDpr);

    ready = true;
    document.documentElement.dataset.faceWorld = "ready";
    window.dispatchEvent(new CustomEvent("master:face-world-ready"));
  }

  async function load() {
    if (ready || updating) return;
    updating = true;
    try {
      const url = new URL(
        window.MASTER_ASSET_PATHS?.threeModule || "/three.face.module.js?v=1",
        document.baseURI
      ).href;
      THREE = await import(url);
      boot();
    } catch (error) {
      document.documentElement.dataset.faceWorld = "error";
      window.MASTER_LOG?.warn?.("face_world:boot", error);
    } finally {
      updating = false;
    }
  }

  function spawnPulse(fromName, toName, energy = 0.5) {
    if (!world || !THREE || pulses.length >= (Number(BUDGET.pulse_limit) || 24)) return;
    const from = nodes.find((node) => node.name === `master-node-${fromName}`);
    const to = nodes.find((node) => node.name === `master-node-${toName}`);
    if (!from || !to) return;

    const geometry = new THREE.SphereGeometry(0.014, 6, 4);
    const material = new THREE.MeshBasicMaterial({
      color: colorFromCss(),
      transparent: true,
      opacity: Math.min(0.9, 0.25 + energy * 0.65),
      depthWrite: false
    });
    const pulse = new THREE.Mesh(geometry, material);
    pulse.name = "master-event-pulse";
    pulse.userData = { from, to, started: nowMs(), life: 900, energy };
    (layers.event_field || world).add(pulse);
    pulses.push(pulse);
  }

  function nowMs() {
    return typeof performance !== "undefined" ? performance.now() : Date.now();
  }

  function updatePulses(now) {
    pulses = pulses.filter((pulse) => {
      const age = now - pulse.userData.started;
      const t = age / pulse.userData.life;
      if (t >= 1) {
        pulse.parent?.remove(pulse);
        pulse.geometry?.dispose?.();
        pulse.material?.dispose?.();
        return false;
      }
      const a = pulse.userData.from.position;
      const b = pulse.userData.to.position;
      pulse.position.lerpVectors(a, b, t);
      pulse.scale.setScalar(0.7 + pulse.userData.energy * Math.sin(Math.PI * t));
      pulse.material.opacity = (1 - t) * Math.min(0.9, 0.25 + pulse.userData.energy * 0.65);
      return true;
    });
  }

  function update(now = performance.now()) {
    if (!ready || !world || !shellMaterial) return;

    const state = window.MASTER_FACE_STATE?.snapshot?.()
      || window.MASTER_FACE?.State
      || {};

    const geometry = window.MASTER_FACE_STATE?.geometryProfile?.(state);
    if (!geometry) return;

    const budget = window.MASTER_FACE_STATE?.renderBudget?.() || {};
    const topology = String(state.topology || "papua-mask");
    const portrait = topology === "face" || topology === "papua-mask";
    const topologyProfile = TOPOLOGY_PROFILES[topology] || TOPOLOGY_PROFILES["papua-mask"] || {};
    const kernel = window.ParticleKernel;
    const eyePool = window.MASTER_FACE?.eyePool;
    const mouthPool = window.MASTER_FACE?.mouthPool;
    if (kernel && eyePool && mouthPool) {
      window.MASTER_FACE_PARTICLES?.reactAudio?.(state, mouthPool);
      for (let i = 0; i < eyePool.count; i += 1) if (eyePool.alive[i]) {
        const base = i * kernel.FIELDS_PER_CELL;
        eyePool.cells[base + kernel.FIELD.attention] = Math.max(
          eyePool.cells[base + kernel.FIELD.attention] || 0,
          geometry.eye_attention * 0.82
        );
      }
      for (let i = 0; i < mouthPool.count; i += 1) if (mouthPool.alive[i]) {
        const base = i * kernel.FIELDS_PER_CELL;
        const speech = state.mode === "speaking" || state.mode === "listening" ? 1 : 0.52;
        mouthPool.cells[base + kernel.FIELD.arousal] = Math.max(
          mouthPool.cells[base + kernel.FIELD.arousal] || 0,
          geometry.mouth_energy * speech
        );
      }
    }
    const density = finite(topologyProfile.density, 1);
    const morphology = SPATIAL.morphology || {};
    const cranialScale = finite(morphology.cranium_scale, 1.12);
    const cranialWidth = finite(morphology.cranial_width, 1.03);
    const upperFaceScale = finite(morphology.upper_face_scale, 0.96);
    const lowerFaceScale = finite(morphology.lower_face_scale, 0.84);
    const facialVerticalization = finite(morphology.facial_verticalization, 1.02);
    const facialProjection = finite(morphology.facial_projection, 0.88);

    const audioEnergy = Math.max(0, Math.min(1, (audio.rms * 0.45) + (audio.mid * 0.35) + (audio.high * 0.20)));
    const audioPulse = Math.max(audio.onset, audio.bass * 0.65);
    const fracture = finite(topologyProfile.fracture, 0);
    const tiltX = finite(topologyProfile.tilt_x, 0);
    const tiltY = finite(topologyProfile.tilt_y, 0);
    const pointerX = finite(window.MASTER_FACE?.State?.mouseX, 0);
    const pointerY = finite(window.MASTER_FACE?.State?.mouseY, 0);
    const cameraLimit = finite(CAMERA.orbit_limit, 0.16);
    const cameraParallax = finite(CAMERA.parallax, geometry.camera_parallax);
    const targetX = Math.max(-cameraLimit, Math.min(cameraLimit, pointerY * cameraParallax));
    const targetY = Math.max(-cameraLimit, Math.min(cameraLimit, pointerX * cameraParallax));

    world.rotation.y += ((pointerX * 0.045) + tiltY * (geometry.fracture + fracture) - world.rotation.y) * 0.035;
    world.rotation.x += ((pointerY * 0.028) + tiltX * (geometry.fracture + fracture) - world.rotation.x) * 0.035;

    shell.scale.set(
      geometry.shell_scale * cranialWidth * upperFaceScale * (1 + audioPulse * 0.018),
      geometry.shell_scale * cranialScale * facialVerticalization * (1 + audioPulse * 0.010),
      geometry.shell_scale * facialProjection * (1 + audioPulse * 0.012)
    );
    shellMaterial.uniforms.uTime.value = now;
    shellMaterial.uniforms.uTension.value = geometry.shell_tension;
    shellMaterial.uniforms.uPulse.value = geometry.shell_pulse;
    shellMaterial.uniforms.uFracture.value = geometry.shell_fracture;
    shellMaterial.uniforms.uOpacity.value = geometry.shell_opacity * (state.mode === "sleeping" ? 0.35 : 1) * (0.88 + audioEnergy * 0.12);
    shellMaterial.uniforms.uEntropy.value = state.entropy;
    shellMaterial.uniforms.uColor.value.copy(colorFromCss());

    nodes.forEach((node) => {
      node.visible = !portrait;
      const phase = node.userData.phase;
      const pulse = 1 + Math.sin(now * 0.0012 + phase) * 0.14 * geometry.neural_density + audioEnergy * 0.08;
      node.scale.setScalar(pulse);
      node.position.z = NODE_LAYOUT[node.userData.index][3] + Math.sin(now * 0.00065 + phase) * 0.05 * geometry.depth;
      node.material.opacity = Math.min(0.85, 0.20 + geometry.neural_density * 0.55 * density);
      node.material.color.copy(shellMaterial.uniforms.uColor.value);
    });

    if (edges) {
      edges.visible = !portrait;
      edges.material.opacity = Math.min(0.28, (0.035 + geometry.neural_density * 0.10) * density);
      edges.material.color.copy(shellMaterial.uniforms.uColor.value);
    }

    if (splatProxy) {
      splatProxy.visible = !portrait;
      splatProxy.material.opacity =
        Math.min(0.18, 0.03 + geometry.neural_density * 0.09 * density + (geometry.fracture + fracture) * 0.04);
      splatProxy.material.color.copy(shellMaterial.uniforms.uColor.value);
      splatProxy.rotation.z = (now * 0.000018 * (0.5 + geometry.depth)) % (Math.PI * 2);
    }

    if (camera) {
      const runtimeState = window.MASTER_FACE?.State || {};
      const baseDistance = finite(CAMERA.distance, geometry.camera_distance);
      const started = finite(runtimeState.cameraZoomAt, 0);
      const zoom = Math.max(0, Math.min(1, finite(runtimeState.cameraZoom, 0)));
      const age = started > 0 ? now - started : Infinity;
      const duration = 3200;
      const progress = Math.max(0, Math.min(1, age / duration));
      let envelope = 0;
      if (zoom > 0 && progress < 1) {
        if (progress < 0.375) {
          const p = progress / 0.375;
          envelope = p < 0.5 ? 2 * p * p : -1 + (4 - 2 * p) * p;
        } else {
          const p = (progress - 0.375) / 0.625;
          envelope = 1 - (p < 0.5 ? 2 * p * p : -1 + (4 - 2 * p) * p);
        }
      } else if (zoom > 0) {
        runtimeState.cameraZoom = 0;
      }

      const targetFov = finite(CAMERA.fov, 38) - envelope * zoom * 10;
      const targetDistance = finite(geometry.camera_distance, baseDistance) + envelope * zoom * 0.55;
      camera.position.z += (targetDistance - camera.position.z) * 0.035;
      camera.position.x += (targetX - camera.position.x) * 0.035;
      camera.position.y += (targetY - camera.position.y) * 0.035;
      camera.fov += (targetFov - camera.fov) * 0.08;
      camera.updateProjectionMatrix?.();
    }

    hudSprites.forEach(({ nodeName, sprite }) => {
      sprite.visible = !portrait;
      const node = nodes.find((item) => item.name === nodeName);
      if (!node) return;
      sprite.position.copy(node.position);
      sprite.position.z += 0.12;
      const busy = Math.max(state.activity, state.arousal);
      sprite.material.opacity = Math.min(0.76, state.mode === "sleeping"
        ? 0.04
        : 0.10 + geometry.eye_attention * 0.12 + geometry.node_energy * 0.34 + busy * 0.18);
    });

    updatePulses(now);

    // The portrait should feel alive without looking busy: a barely perceptible
    // breath keeps the head from freezing while leaving operator attention on the eyes.
    const breath = Math.sin(now * 0.00072) * (state.mode === "idle" ? 0.008 : 0.004);
    world.position.y += (breath - world.position.y) * 0.08;

    const activePoints = Math.max(0, Math.min(splatCount, Number(budget.points || 420)));
    if (splatProxy) {
      splatProxy.geometry.setDrawRange(0, activePoints);
      splatProxy.visible = activePoints > 0;
      splatProxy.material.opacity = Math.min(
        0.18,
        0.03 + geometry.neural_density * 0.09 * density + (geometry.fracture + fracture) * 0.04
      );
    }

    // All legacy visual projections consume this same frame; none schedules time.
    window.MASTEREcologyRender?.update?.(now);
    window.MASTER_GRAVITY_FIELD?.update?.(now);

    document.documentElement.style.setProperty("--master-face-depth", geometry.depth.toFixed(3));
    document.documentElement.style.setProperty("--master-face-tension", geometry.shell_tension.toFixed(3));
    document.documentElement.style.setProperty("--master-audio-energy", audioEnergy.toFixed(3));
    window.MasterRenderPolicy?.recordFrame?.(now);
  }

  window.MASTER_FACE_WORLD = Object.freeze({ load, update, spawnPulse });
  window.addEventListener("master:visual", (event) => {
    const detail = event.detail || {};
    const name = String(detail.name || detail.mode || "");
    if (/llm:|route:resolved|tool:call|pipeline:stage_start|fix_loop:pass_start/.test(name)) {
      const from = /tool|fetch|write|read/.test(name) ? "tools" : /fix|pipeline/.test(name) ? "lib" : "law";
      const to = from === "tools" ? "web" : from === "lib" ? "tools" : "lib";
      spawnPulse(from, to, Number(detail.activity || detail.confidence || 0.5));
    }
  }, { passive: true });
  window.addEventListener("master:face-ready", () => load(), { once: true });
  if (window._primerFired) load();
})();
