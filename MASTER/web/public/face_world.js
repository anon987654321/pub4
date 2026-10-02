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

  const TOPOLOGY_TILT = Object.freeze({
    "codebase": [0.00, 0.18],
    "neural": [0.12, -0.08],
    "terrain": [-0.08, 0.10],
    "glitch": [0.18, 0.24],
    "serpent": [0.14, -0.20],
    "torus": [-0.14, 0.16],
    "sphere": [0.00, 0.00],
    "papua-mask": [0.00, 0.00]
  });

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
    const geometry = new THREE.SphereGeometry(1.58, 28, 20);
    shellMaterial = new THREE.ShaderMaterial({
      uniforms: {
        uTime: { value: 0 },
        uTension: { value: 0.24 },
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
        "  float ripple = sin(p.y * 7.0 + uTime * 0.00055) * sin(p.x * 5.0 - uTime * 0.00031);",
        "  p += normal * ripple * 0.018 * (0.25 + uTension);",
        "  gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);",
        "}"
      ].join("\n"),
      fragmentShader: [
        "uniform float uOpacity;",
        "uniform float uEntropy;",
        "uniform vec3 uColor;",
        "varying vec3 vNormal;",
        "varying vec3 vPosition;",
        "void main() {",
        "  float shell = abs(sin(vPosition.y * 11.0 + vPosition.x * 5.0));",
        "  float contour = smoothstep(0.92, 0.985, shell);",
        "  float latitude = smoothstep(0.985, 1.0, abs(vNormal.z));",
        "  float alpha = contour * uOpacity + latitude * uOpacity * 0.35;",
        "  alpha *= 0.65 + uEntropy * 0.35;",
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
    world.add(shell);
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
      world.add(node);
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
    world.add(edges);
  }

  function makeSplatProxy() {
    const count = 384;
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
    world.add(splatProxy);

    document.documentElement.dataset.faceSplatMode =
      typeof THREE.GaussianSplat === "function" ? "native-capable-proxy" : "deterministic-points";
  }

  function boot() {
    if (ready || !window.MASTER_FACE?.scene) return;

    const scene = window.MASTER_FACE.scene;
    world = new THREE.Group();
    world.name = "master-face-world";

    const host = window.MASTER_FACE.head || scene;
    host.add(world);

    makeShell();
    makeNodes();
    makeSplatProxy();

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

  function update(now = performance.now()) {
    if (!ready || !world || !shellMaterial) return;

    const state = window.MASTER_FACE_STATE?.snapshot?.()
      || window.MASTER_FACE?.State
      || {};

    const geometry = window.MASTER_FACE_STATE?.geometryProfile?.(state);
    if (!geometry) return;

    const topology = String(state.topology || "papua-mask");
    const tilt = TOPOLOGY_TILT[topology] || TOPOLOGY_TILT["papua-mask"];
    const pointerX = finite(window.MASTER_FACE?.State?.mouseX, 0);
    const pointerY = finite(window.MASTER_FACE?.State?.mouseY, 0);

    world.rotation.y += ((pointerX * 0.045) + tilt[1] * geometry.fracture - world.rotation.y) * 0.035;
    world.rotation.x += ((pointerY * 0.028) + tilt[0] * geometry.fracture - world.rotation.x) * 0.035;

    shell.scale.setScalar(geometry.shell_scale);
    shellMaterial.uniforms.uTime.value = now;
    shellMaterial.uniforms.uTension.value = geometry.shell_tension;
    shellMaterial.uniforms.uOpacity.value = geometry.shell_opacity * (state.mode === "sleeping" ? 0.35 : 1);
    shellMaterial.uniforms.uEntropy.value = state.entropy;
    shellMaterial.uniforms.uColor.value.copy(colorFromCss());

    nodes.forEach((node) => {
      const phase = node.userData.phase;
      const pulse = 1 + Math.sin(now * 0.0012 + phase) * 0.14 * geometry.neural_density;
      node.scale.setScalar(pulse);
      node.position.z = NODE_LAYOUT[node.userData.index][3] + Math.sin(now * 0.00065 + phase) * 0.05 * geometry.depth;
      node.material.opacity = Math.min(0.85, 0.20 + geometry.neural_density * 0.55);
      node.material.color.copy(shellMaterial.uniforms.uColor.value);
    });

    if (edges) {
      edges.material.opacity = 0.035 + geometry.neural_density * 0.10;
      edges.material.color.copy(shellMaterial.uniforms.uColor.value);
    }

    if (splatProxy) {
      splatProxy.material.opacity =
        Math.min(0.18, 0.03 + geometry.neural_density * 0.09 + geometry.fracture * 0.04);
      splatProxy.material.color.copy(shellMaterial.uniforms.uColor.value);
      splatProxy.rotation.z = now * 0.000018 * (0.5 + geometry.depth);
    }

    // All legacy visual projections consume this same frame; none schedules time.
    window.MASTEREcologyRender?.update?.(now);
    window.MASTER_GRAVITY_FIELD?.update?.(now);

    document.documentElement.style.setProperty("--master-face-depth", geometry.depth.toFixed(3));
    document.documentElement.style.setProperty("--master-face-tension", geometry.shell_tension.toFixed(3));
  }

  window.MASTER_FACE_WORLD = Object.freeze({ load, update });
  window.addEventListener("master:face-ready", () => load(), { once: true });
  if (window._primerFired) load();
})();
