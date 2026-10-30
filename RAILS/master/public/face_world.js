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
  let splatBasePositions = null;
  let splatTargetPositions = null;
  let semanticForm = "face";
  let semanticBlend = 0;
  let semanticBlendTarget = 0;
  let semanticMorphInProgress = false;
  let nativeSubjectField = false;
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
  const TASK_RING = SPATIAL.task_ring || {};
  const LAYER_NAMES = Array.isArray(SPATIAL.layers)
    ? SPATIAL.layers.map((name) => String(name))
    : ["identity", "eyes", "mouth", "cognition", "repository", "event_field", "camera", "hud"];
  const activityRecords = new Map();
  const activityMeshes = new Map();
  let activityGeometry = null;
  let activityOrder = 0;

  function finite(value, fallback) {
    const number = Number(value);
    return Number.isFinite(number) ? number : fallback;
  }

  function reducedMotionEnabled(state = {}) {
    const canonical = window.MASTER_FACE_STATE?.reducedMotion;
    if (typeof canonical === "function") return canonical(state);
    // Compatibility fallback for an older shell without the canonical state bridge.
    return Boolean(state?.reducedMotion) ||
      Boolean(window.MASTER_FACE?.State?.reducedMotion) ||
      document.documentElement?.dataset?.reducedMotion === "1" ||
      Boolean(window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches);
  }

  const SUBJECT_FORMS = new Set(["face", "fugue", "wave", "orbit", "architecture", "leaf", "network", "constellation"]);
  const SUBJECT_HINTS = [
    ["fugue", /\b(fugue|counterpoint|polyphony|music|melody|rhythm|beat|jazz|dilla|song|harmony|symphony|tempo|chord)\b/i],
    ["wave", /\b(audio|sound|wave|frequency|signal|radio|spectrum|pitch|voice|speech|vibration)\b/i],
    ["architecture", /\b(architecture|building|house|bridge|city|structure|tower|room|design|geometry|facade)\b/i],
    ["leaf", /\b(nature|forest|tree|leaf|plant|garden|ecology|flower|root|branch|growth)\b/i],
    ["orbit", /\b(space|planet|cosmos|star|orbit|galaxy|solar|universe|astronomy|celestial)\b/i],
    ["network", /\b(network|graph|system|code|program|repo|repository|dependency|software|git|master|rails|openbsd|studio|github|test|fix|api|model|latency)\b/i]
  ];

  function inferSubjectForm(value) {
    const text = String(value || "").normalize("NFKC").slice(0, 6000);
    if (!text.trim()) return "face";
    return SUBJECT_HINTS.find(([, pattern]) => pattern.test(text))?.[0] || "constellation";
  }

  function buildSubjectPositions(form) {
    if (!splatBasePositions) return null;
    if (form === "face") return splatBasePositions.slice();

    const positions = new Float32Array(splatBasePositions.length);
    const count = splatCount;
    const centers = [
      [-1.05, -0.72, 0.06], [-0.38, 0.78, -0.24], [0.58, 0.28, 0.15],
      [1.03, -0.62, -0.20], [0.18, -0.12, 0.45], [-0.76, 0.24, 0.34], [0.72, 0.88, -0.35]
    ];
    for (let i = 0; i < count; i += 1) {
      const u = (i + 0.5) / count;
      const b = seeded(i, 32);
      const c = seeded(i, 33);
      let x = 0, y = 0, z = 0;
      if (form === "fugue") {
        const strand = i % 3;
        const angle = u * Math.PI * 6 + strand * Math.PI * 2 / 3;
        const radius = 0.48 + b * 0.18;
        x = Math.cos(angle) * radius;
        y = (u - 0.5) * 3.25;
        z = Math.sin(angle) * radius;
      } else if (form === "wave") {
        x = (u - 0.5) * 3.35;
        y = Math.sin(u * Math.PI * 6 + b * 0.45) * 0.68 + (b - 0.5) * 0.18;
        z = (c - 0.5) * 0.38;
      } else if (form === "orbit") {
        const plane = i % 3;
        const angle = u * Math.PI * 4 + (b - 0.5) * 0.22;
        const radius = 0.78 + c * 0.32;
        if (plane === 0) { x = Math.cos(angle) * radius; y = Math.sin(angle) * radius; z = (b - 0.5) * 0.08; }
        else if (plane === 1) { x = Math.cos(angle) * radius; y = (b - 0.5) * 0.08; z = Math.sin(angle) * radius; }
        else { x = (b - 0.5) * 0.08; y = Math.cos(angle) * radius; z = Math.sin(angle) * radius; }
      } else if (form === "architecture") {
        const level = Math.floor(u * 11);
        const taper = 0.34 + 0.48 * (1 - level / 10);
        x = (Math.floor(b * 7) - 3) * taper * 0.16;
        y = (level / 10 - 0.5) * 3.0;
        z = (Math.floor(c * 7) - 3) * 0.16;
      } else if (form === "leaf") {
        y = (u - 0.5) * 3.15;
        const width = Math.sin(Math.PI * u) * 1.45;
        x = (b - 0.5) * width;
        z = (c - 0.5) * 0.22 + x * 0.06;
        if (i % 9 === 0) { x = 0; z = 0.02; }
      } else if (form === "network") {
        x = (Math.floor(b * 9) - 4) * 0.29;
        y = (Math.floor(u * 11) - 5) * 0.28;
        z = (Math.floor(c * 9) - 4) * 0.29;
      } else {
        const center = centers[Math.floor(seeded(i, 34) * centers.length)];
        x = center[0] + (b - 0.5) * 0.44;
        y = center[1] + (seeded(i, 35) - 0.5) * 0.44;
        z = center[2] + (c - 0.5) * 0.44;
      }
      const offset = i * 3;
      positions[offset] = x;
      positions[offset + 1] = y;
      positions[offset + 2] = z;
    }
    return positions;
  }

  // The head's primary point field uses normalized coordinates around +/-0.62.
  // Reuse its real vertex count so a theme morphs the face itself rather than only
  // adding a second cloud around it.
  function buildFaceSubjectPositions(form) {
    const faceScatter = window.MASTER_FACE?.faceScatter;
    if (!faceScatter || faceScatter.length < 3 || faceScatter.length % 3 !== 0) return null;

    const count = faceScatter.length / 3;
    const positions = new Float32Array(faceScatter.length);
    const centers = [
      [-0.38, -0.28, 0.02], [-0.16, 0.31, -0.08], [0.18, 0.12, 0.06],
      [0.38, -0.24, -0.05], [0.08, -0.04, 0.24], [-0.28, 0.10, 0.18],
      [0.28, 0.36, -0.18]
    ];

    for (let i = 0; i < count; i += 1) {
      const u = (i + 0.5) / count;
      const b = seeded(i, 32);
      const c = seeded(i, 33);
      let x = 0, y = 0, z = 0;

      if (form === "fugue") {
        const strand = i % 3;
        const angle = u * Math.PI * 6 + strand * Math.PI * 2 / 3;
        const radius = 0.20 + b * 0.11;
        x = Math.cos(angle) * radius;
        y = (u - 0.5) * 1.16;
        z = Math.sin(angle) * radius;
      } else if (form === "wave") {
        x = (u - 0.5) * 1.14;
        y = Math.sin(u * Math.PI * 6 + b * 0.45) * 0.24 + (b - 0.5) * 0.07;
        z = (c - 0.5) * 0.16;
      } else if (form === "orbit") {
        const plane = i % 3;
        const angle = u * Math.PI * 4 + (b - 0.5) * 0.22;
        const radius = 0.34 + c * 0.12;
        if (plane === 0) { x = Math.cos(angle) * radius; y = Math.sin(angle) * radius; z = (b - 0.5) * 0.06; }
        else if (plane === 1) { x = Math.cos(angle) * radius; y = (b - 0.5) * 0.06; z = Math.sin(angle) * radius; }
        else { x = (b - 0.5) * 0.06; y = Math.cos(angle) * radius; z = Math.sin(angle) * radius; }
      } else if (form === "architecture") {
        const level = Math.floor(u * 13);
        const taper = 0.30 + 0.42 * (1 - level / 12);
        x = (Math.floor(b * 7) - 3) * taper * 0.11;
        y = (level / 12 - 0.5) * 1.16;
        z = (Math.floor(c * 7) - 3) * 0.11;
      } else if (form === "leaf") {
        y = (u - 0.5) * 1.18;
        const width = Math.sin(Math.PI * u) * 0.56;
        x = (b - 0.5) * width;
        z = (c - 0.5) * 0.12 + x * 0.06;
        if (i % 9 === 0) { x = 0; z = 0.01; }
      } else if (form === "network") {
        x = (Math.floor(b * 9) - 4) * 0.125;
        y = (Math.floor(u * 11) - 5) * 0.112;
        z = (Math.floor(c * 9) - 4) * 0.125;
      } else {
        const center = centers[Math.floor(seeded(i, 34) * centers.length)];
        x = center[0] + (b - 0.5) * 0.22;
        y = center[1] + (seeded(i, 35) - 0.5) * 0.22;
        z = center[2] + (c - 0.5) * 0.22;
      }

      const offset = i * 3;
      positions[offset] = x;
      positions[offset + 1] = y;
      positions[offset + 2] = z;
    }
    return positions;
  }

  function setSubjectForm(value) {
    const form = SUBJECT_FORMS.has(String(value || "").toLowerCase())
      ? String(value).toLowerCase()
      : "constellation";
    if (form === semanticForm && splatTargetPositions) return form;
    semanticForm = form;
    semanticBlendTarget = form === "face" ? 0 : 1;
    splatTargetPositions = buildSubjectPositions(form);

    const facePositions = form === "face" ? null : buildFaceSubjectPositions(form);
    nativeSubjectField = form === "face"
      ? window.MASTER_FACE?.resetSubjectScatter?.() === true
      : Boolean(facePositions && window.MASTER_FACE?.setSubjectScatter?.(facePositions) === true);
    // If the primary renderer can take the semantic field, let its actual face
    // vertices morph and keep the secondary cloud dormant. Older/no-WebGL builds
    // retain the bounded FaceWorld cloud as a graceful fallback.
    semanticMorphInProgress = nativeSubjectField ? false : Boolean(splatTargetPositions);
    document.documentElement.dataset.faceSubject = form;
    document.documentElement.dataset.faceSubjectRenderer = nativeSubjectField ? "primary-points" : "face-world-fallback";
    window.dispatchEvent(new CustomEvent("master:face-subject", {
      detail: { form, active: semanticBlendTarget > 0, renderer: nativeSubjectField ? "primary-points" : "face-world-fallback" }
    }));
    return form;
  }

  function setSubjectFromText(value) {
    return setSubjectForm(inferSubjectForm(value));
  }

  // The semantic subject follows the active conversation and returns to the
  // resting face after inactivity. Switching between two non-face subjects
  // passes through the resting geometry because the primary renderer has one
  // scatter target; replacing it in place snaps when the morph is at its limit.
  const SUBJECT_IDLE_RESTORE_MS = 45_000;
  const SUBJECT_MORPH_SETTLE_TIMEOUT_MS = 2_400;
  let subjectRestoreTimer = null;
  let subjectTransitionTimer = null;
  let pendingSubjectForm = null;
  let subjectTransitionGeneration = 0;

  function clearSubjectRestoreTimer() {
    if (subjectRestoreTimer) clearTimeout(subjectRestoreTimer);
    subjectRestoreTimer = null;
  }

  function restoreFaceSubject() {
    clearSubjectRestoreTimer();
    if (subjectTransitionTimer) clearTimeout(subjectTransitionTimer);
    subjectTransitionTimer = null;
    pendingSubjectForm = null;
    subjectTransitionGeneration += 1;
    return setSubjectForm("face");
  }

  function setConversationSubject(value) {
    const next = inferSubjectForm(value);
    if (next === semanticForm && !pendingSubjectForm) return next;

    const currentMorph = Number(window.MASTER_FACE?.morphCurrent);
    const faceStillMorphing = semanticForm === "face" && nativeSubjectField &&
      Number.isFinite(currentMorph) && currentMorph < 0.995;

    if (next !== "face" && pendingSubjectForm && semanticForm === "face") {
      pendingSubjectForm = next;
      return next;
    }

    if (next !== "face" && !reducedMotionEnabled() &&
        (semanticForm !== "face" || faceStillMorphing)) {
      if (subjectTransitionTimer) clearTimeout(subjectTransitionTimer);
      pendingSubjectForm = next;
      const generation = ++subjectTransitionGeneration;
      if (semanticForm !== "face") setSubjectForm("face");
      const deadline = Date.now() + SUBJECT_MORPH_SETTLE_TIMEOUT_MS;
      const advanceWhenFaceIsResting = () => {
        if (generation !== subjectTransitionGeneration) return;
        const morph = Number(window.MASTER_FACE?.morphCurrent);
        if (!Number.isFinite(morph) || morph >= 0.995 || Date.now() >= deadline) {
          const form = pendingSubjectForm;
          pendingSubjectForm = null;
          subjectTransitionTimer = null;
          if (form && form !== "face") setSubjectForm(form);
          return;
        }
        subjectTransitionTimer = setTimeout(advanceWhenFaceIsResting, 40);
      };
      subjectTransitionTimer = setTimeout(advanceWhenFaceIsResting, 40);
      return next;
    }

    if (subjectTransitionTimer) clearTimeout(subjectTransitionTimer);
    subjectTransitionTimer = null;
    pendingSubjectForm = null;
    subjectTransitionGeneration += 1;
    return setSubjectForm(next);
  }

  function scheduleFaceRestoration() {
    clearSubjectRestoreTimer();
    subjectRestoreTimer = setTimeout(() => {
      subjectRestoreTimer = null;
      restoreFaceSubject();
    }, SUBJECT_IDLE_RESTORE_MS);
  }

  const TERMINAL_ACTIVITY_STATES = new Set(["complete", "failed", "cancelled"]);

  function removeActivity(key) {
    const mesh = activityMeshes.get(key);
    if (mesh) {
      mesh.parent?.remove(mesh);
      mesh.material?.dispose?.();
      activityMeshes.delete(key);
    }
    activityRecords.delete(key);
  }

  function ensureActivityMesh(record) {
    if (!TASK_RING.enabled || !world || !THREE || !activityGeometry || activityMeshes.has(record.key)) return;
    const mesh = new THREE.Mesh(activityGeometry, new THREE.MeshBasicMaterial({
      color: colorFromCss(),
      transparent: true,
      opacity: 0.32,
      depthWrite: false
    }));
    mesh.name = "master-activity-" + record.kind;
    mesh.userData.activityKey = record.key;
    (layers.event_field || world).add(mesh);
    activityMeshes.set(record.key, mesh);
  }

  function rememberActivity(kind, record = {}) {
    if (!TASK_RING.enabled) return null;
    const id = String(record.id || "").trim();
    if (!id) return null;
    const key = kind + ":" + id;
    const previous = activityRecords.get(key);
    const state = String(record.state || (kind === "evidence" ? "evidence" : "queued"));
    const terminalAt = TERMINAL_ACTIVITY_STATES.has(state)
      ? (previous?.terminalAt || Date.now())
      : 0;
    const item = {
      key,
      id,
      kind,
      state,
      label: String(record.kind || record.data?.label || record.data?.name || record.recordType || kind),
      createdAt: finite(record.createdAt, previous?.createdAt || Date.now()),
      updatedAt: finite(record.updatedAt, Date.now()),
      terminalAt,
      order: previous?.order ?? activityOrder++
    };
    activityRecords.set(key, item);

    const limit = Math.max(1, Math.min(24, Math.floor(finite(TASK_RING.max_nodes, 12))));
    while (activityRecords.size > limit) {
      const oldest = [...activityRecords.values()].sort((a, b) => {
        if (Boolean(a.terminalAt) !== Boolean(b.terminalAt)) return a.terminalAt ? -1 : 1;
        return a.order - b.order;
      })[0];
      if (!oldest) break;
      removeActivity(oldest.key);
    }

    ensureActivityMesh(item);
    return item;
  }

  function isEvidenceRecord(record) {
    return String(record?.type || record?.recordType || "").toLowerCase().includes("evidence");
  }

  function syncActivitySnapshot() {
    const snapshot = window.MasterInteraction?.snapshot?.() || {};
    (snapshot.task?.records || []).forEach((record) => rememberActivity("task", record));
    (snapshot.tool?.records || []).forEach((record) => rememberActivity("tool", record));
    (snapshot.memory?.records || []).filter(isEvidenceRecord).forEach((record) => rememberActivity("evidence", record));
    for (const record of activityRecords.values()) ensureActivityMesh(record);
  }

  function updateActivityNodes(now, state, reducedMotion = false) {
    const ttl = Math.max(0, finite(TASK_RING.terminal_lifetime_ms, 12000));
    if (ttl > 0) {
      const wallNow = Date.now();
      for (const record of activityRecords.values()) {
        if (record.terminalAt && wallNow - record.terminalAt >= ttl) removeActivity(record.key);
      }
    }

    const records = [...activityRecords.values()].sort((a, b) => a.order - b.order);
    const radiusX = finite(TASK_RING.radius_x, 2.02);
    const radiusY = finite(TASK_RING.radius_y, 1.72);
    const depth = finite(TASK_RING.depth, -0.12);
    const orbitSpeed = finite(TASK_RING.orbit_speed, 0.000004);
    const color = shellMaterial?.uniforms?.uColor?.value || colorFromCss();
    records.forEach((record, index) => {
      const mesh = activityMeshes.get(record.key);
      if (!mesh) return;
      const radiusScale = record.kind === "evidence" ? 1.12 : record.kind === "tool" ? 1.04 : 1;
      const stillMode = window.MASTER_FACE_STATE?.isStillMode?.(state.mode) ?? state.mode === "idle";
      const angle = (Math.PI * 2 * index / Math.max(1, records.length)) +
        (reducedMotion || stillMode ? 0 : now * orbitSpeed);
      mesh.position.set(
        Math.cos(angle) * radiusX * radiusScale,
        Math.sin(angle) * radiusY * radiusScale,
        depth + Math.sin(angle * 1.7) * 0.045
      );
      const active = record.state === "active" || record.state === "queued" || record.state === "retry";
      const waiting = record.state.startsWith("waiting");
      const baseOpacity = record.state === "failed" ? 0.76
        : record.state === "complete" || record.state === "cancelled" ? 0.19
        : waiting ? 0.48
        : record.kind === "evidence" ? 0.34
        : active ? 0.64 : 0.40;
      const pulse = !reducedMotion && !stillMode && active
        ? 0.12 * (0.5 + 0.5 * Math.sin(now * 0.004 + index)) : 0;
      const terminalFade = !reducedMotion && record.terminalAt && ttl > 0
        ? Math.max(0, 1 - (Date.now() - record.terminalAt) / ttl) : 1;
      mesh.material.opacity = Math.min(0.9, (baseOpacity + pulse) * terminalFade
        * (state.mode === "sleeping" ? 0.55 : 1));
      mesh.material.color.copy(color);
      const scale = record.state === "failed" ? 1.24 : active ? 1.16 : waiting ? 1.02
        : record.kind === "evidence" ? 0.76 : 0.82;
      mesh.scale.setScalar(scale * (1 + pulse * 0.55));
    });
  }

  function handleActivityEvent(kind, event) {
    const detail = event.detail || {};
    if (kind === "evidence") {
      const recordType = detail.recordType || "evidence";
      if (!String(recordType).toLowerCase().includes("evidence")) return;
      rememberActivity("evidence", { ...detail, type: recordType, state: "evidence" });
      return;
    }
    rememberActivity(kind, detail);
  }

  [
    "task:queued", "task:active", "task:waiting-human", "task:waiting-network",
    "task:waiting-model", "task:complete", "task:failed", "task:cancelled"
  ].forEach((name) => window.addEventListener(name, (event) => handleActivityEvent("task", event), { passive: true }));
  ["tool:queued", "tool:active", "tool:retry", "tool:complete", "tool:failed"]
    .forEach((name) => window.addEventListener(name, (event) => handleActivityEvent("tool", event), { passive: true }));
  window.addEventListener("memory:added", (event) => handleActivityEvent("evidence", event), { passive: true });

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
    // FaceState owns the split. Older shells with only the total budget still
    // derive their share from the canonical allocation instead of taking the total.
    const effectiveBudget = window.MASTER_FACE_STATE?.renderBudget?.() || {};
    const mobile = Boolean(window.matchMedia?.("(pointer: coarse)")?.matches) ||
      Boolean(window.matchMedia?.("(max-width: 767px)")?.matches) || Number(window.navigator?.hardwareConcurrency || 8) <= 4;
    const fallbackTotal = Number(BUDGET[mobile ? "mobile_points" : "desktop_points"]) || (mobile ? 420 : 1200);
    const totalValue = Number(effectiveBudget.points ?? fallbackTotal);
    const total = Number.isFinite(totalValue) && totalValue > 0 ? totalValue : fallbackTotal;
    const allocation = BUDGET.point_allocation || {};
    const stippleWeight = Math.max(0.1, Number(allocation.stipple_fraction) || 0.75);
    const worldWeight = Math.max(0.1, Number(allocation.world_fraction) || 0.25);
    const fallbackShare = Math.max(1, Math.floor(total * worldWeight / (stippleWeight + worldWeight)));
    const sharedWorld = Number(effectiveBudget.world_points);
    const configured = Number.isFinite(sharedWorld) && sharedWorld > 0 ? sharedWorld : fallbackShare;
    const ceiling = Number.isFinite(configured) && configured > 0
      ? Math.min(1200, Math.floor(configured))
      : Math.min(1200, fallbackShare);
    const count = Math.max(1, ceiling);
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

    splatBasePositions = positions.slice();
    splatTargetPositions = buildSubjectPositions(semanticForm);
    semanticMorphInProgress = !nativeSubjectField && semanticForm !== "face";
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
    activityGeometry = new THREE.SphereGeometry(
      Math.max(0.012, finite(TASK_RING.dot_radius, 0.027)), 8, 6
    );

    const budget = window.MASTER_FACE_STATE?.renderBudget?.() || {};
    const initialDpr = Math.min(Number(budget.dpr || 1), Number(BUDGET.max_device_pixel_ratio || 2));
    document.documentElement.style.setProperty("--master-face-points", String(Math.min(
      Number(budget.points || 420),
      Number(BUDGET.desktop_points || 1200)
    )));
    if (window.MASTER_FACE?.renderer?.setPixelRatio) window.MASTER_FACE.renderer.setPixelRatio(initialDpr);

    ready = true;
    syncActivitySnapshot();
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

  function updatePulses(now, reducedMotion = false) {
    pulses = pulses.filter((pulse) => {
      const age = now - pulse.userData.started;
      if (age >= pulse.userData.life) {
        pulse.parent?.remove(pulse);
        pulse.geometry?.dispose?.();
        pulse.material?.dispose?.();
        return false;
      }
      const t = reducedMotion ? 0.5 : age / pulse.userData.life;
      const a = pulse.userData.from.position;
      const b = pulse.userData.to.position;
      pulse.position.lerpVectors(a, b, t);
      pulse.scale.setScalar(reducedMotion ? 0.7 + pulse.userData.energy * 0.5 : 0.7 + pulse.userData.energy * Math.sin(Math.PI * t));
      pulse.material.opacity = reducedMotion
        ? Math.min(0.78, 0.25 + pulse.userData.energy * 0.4)
        : (1 - t) * Math.min(0.9, 0.25 + pulse.userData.energy * 0.65);
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
    const reducedMotion = reducedMotionEnabled(state);
    const stillMode = window.MASTER_FACE_STATE?.isStillMode?.(state.mode) ?? state.mode === "idle";
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
    const audioPulse = reducedMotion || stillMode ? 0 : Math.max(audio.onset, audio.bass * 0.65);
    const fracture = finite(topologyProfile.fracture, 0);
    const tiltX = finite(topologyProfile.tilt_x, 0);
    const tiltY = finite(topologyProfile.tilt_y, 0);
    const pointerX = finite(window.MASTER_FACE?.State?.mouseX, 0);
    const pointerY = finite(window.MASTER_FACE?.State?.mouseY, 0);
    const cameraLimit = finite(CAMERA.orbit_limit, 0.16);
    const cameraParallax = finite(CAMERA.parallax, geometry.camera_parallax);
    const targetX = reducedMotion ? 0 : Math.max(-cameraLimit, Math.min(cameraLimit, pointerY * cameraParallax));
    const targetY = reducedMotion ? 0 : Math.max(-cameraLimit, Math.min(cameraLimit, pointerX * cameraParallax));

    const targetRotationY = (reducedMotion ? 0 : pointerX * 0.045) + tiltY * (geometry.fracture + fracture);
    const targetRotationX = (reducedMotion ? 0 : pointerY * 0.028) + tiltX * (geometry.fracture + fracture);
    const rotationEase = reducedMotion ? 1 : 0.035;
    world.rotation.y += (targetRotationY - world.rotation.y) * rotationEase;
    world.rotation.x += (targetRotationX - world.rotation.x) * rotationEase;

    shell.scale.set(
      geometry.shell_scale * cranialWidth * upperFaceScale * (1 + audioPulse * 0.018),
      geometry.shell_scale * cranialScale * facialVerticalization * (1 + audioPulse * 0.010),
      geometry.shell_scale * facialProjection * (1 + audioPulse * 0.012)
    );
    shellMaterial.uniforms.uTime.value = reducedMotion || stillMode ? 0 : now;
    shellMaterial.uniforms.uTension.value = geometry.shell_tension;
    shellMaterial.uniforms.uPulse.value = geometry.shell_pulse;
    shellMaterial.uniforms.uFracture.value = geometry.shell_fracture;
    const subjectShellOpacity = nativeSubjectField ? (1 - semanticBlend) : (1 - semanticBlend * 0.68);
    shellMaterial.uniforms.uOpacity.value =
      geometry.shell_opacity * (state.mode === "sleeping" ? 0.35 : 1) *
      (0.88 + (reducedMotion ? 0 : audioEnergy) * 0.12) * subjectShellOpacity;
    shellMaterial.uniforms.uEntropy.value = state.entropy;
    shellMaterial.uniforms.uColor.value.copy(colorFromCss());

    nodes.forEach((node) => {
      node.visible = !portrait;
      const phase = node.userData.phase;
      const pulse = reducedMotion || stillMode ? 1 : 1 + Math.sin(now * 0.0012 + phase) * 0.14 * geometry.neural_density + audioEnergy * 0.08;
      node.scale.setScalar(pulse);
      node.position.z = NODE_LAYOUT[node.userData.index][3] + (reducedMotion || stillMode ? 0 : Math.sin(now * 0.00065 + phase) * 0.05 * geometry.depth);
      node.material.opacity = Math.min(0.85, 0.20 + geometry.neural_density * 0.55 * density);
      node.material.color.copy(shellMaterial.uniforms.uColor.value);
    });

    if (edges) {
      edges.visible = !portrait;
      edges.material.opacity = Math.min(0.28, (0.035 + geometry.neural_density * 0.10) * density);
      edges.material.color.copy(shellMaterial.uniforms.uColor.value);
    }

    if (camera) {
      const runtimeState = window.MASTER_FACE?.State || {};
      const baseDistance = finite(CAMERA.distance, geometry.camera_distance);
      const started = finite(runtimeState.cameraZoomAt, 0);
      const zoom = Math.max(0, Math.min(1, finite(runtimeState.cameraZoom, 0)));
      const age = started > 0 ? now - started : Infinity;
      const duration = 3200;
      const progress = reducedMotion ? 1 : Math.max(0, Math.min(1, age / duration));
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
      const cameraEase = reducedMotion ? 1 : 0.035;
      const fovEase = reducedMotion ? 1 : 0.08;
      camera.position.z += (targetDistance - camera.position.z) * cameraEase;
      camera.position.x += (targetX - camera.position.x) * cameraEase;
      camera.position.y += (targetY - camera.position.y) * cameraEase;
      camera.fov += (targetFov - camera.fov) * fovEase;
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

    updateActivityNodes(now, state, reducedMotion);
    updatePulses(now, reducedMotion);

    // Reduced motion keeps the semantic composition but removes idle breathing.
    if (reducedMotion || stillMode) {
      world.position.y = 0;
    } else {
      const breath = Math.sin(now * 0.00072) * (state.mode === "idle" ? 0.008 : 0.004);
      world.position.y += (breath - world.position.y) * 0.08;
    }

    const activePoints = Math.max(0, Math.min(splatCount, Number(budget.points || 420)));
    semanticBlend = reducedMotion
      ? semanticBlendTarget
      : semanticBlend + (semanticBlendTarget - semanticBlend) * 0.045;
    const primaryMorphValue = Number(window.MASTER_FACE?.morphCurrent);
    if (nativeSubjectField && semanticForm === "face" && semanticBlend <= 0.012 &&
        (!Number.isFinite(primaryMorphValue) || primaryMorphValue > 0.995)) {
      nativeSubjectField = false;
    }
    if (splatProxy) {
      const positionAttribute = splatProxy.geometry.getAttribute("position");
      const positions = positionAttribute?.array;
      if (semanticMorphInProgress && positions && splatTargetPositions) {
        const ease = reducedMotion ? 1 : 0.065;
        let settled = true;
        for (let index = 0; index < positions.length; index += 1) {
          const target = splatTargetPositions[index];
          const next = positions[index] + (target - positions[index]) * ease;
          positions[index] = Math.abs(target - next) < 0.0005 ? target : next;
          if (positions[index] !== target) settled = false;
        }
        positionAttribute.needsUpdate = true;
        semanticMorphInProgress = !settled;
      }
      splatProxy.geometry.setDrawRange(0, activePoints);
      const subjectActive = semanticBlend > 0.012 || semanticBlendTarget > 0.012;
      const primaryMorphActive = nativeSubjectField && (semanticForm !== "face" || semanticBlend > 0.012);
      splatProxy.visible = activePoints > 0 && !primaryMorphActive && (!portrait || subjectActive);
      splatProxy.material.opacity = Math.min(
        0.28,
        0.03 + geometry.neural_density * 0.09 * density +
          (geometry.fracture + fracture) * 0.04 + semanticBlend * 0.16
      );
      splatProxy.material.color.copy(shellMaterial.uniforms.uColor.value);
      splatProxy.rotation.z = reducedMotion || stillMode ? 0 :
        (now * 0.000018 * (0.5 + geometry.depth)) % (Math.PI * 2);
    }
    const faceCanvas = document.getElementById("face");
    if (faceCanvas) faceCanvas.style.opacity = nativeSubjectField ? "1" : (1 - semanticBlend * 0.58).toFixed(3);
    document.documentElement.style.setProperty("--master-face-subject-blend", semanticBlend.toFixed(3));

    // All legacy visual projections consume this same frame; none schedules time.
    window.MASTEREcologyRender?.update?.(now);
    window.MASTER_GRAVITY_FIELD?.update?.(now);

    document.documentElement.style.setProperty("--master-face-depth", geometry.depth.toFixed(3));
    document.documentElement.style.setProperty("--master-face-tension", geometry.shell_tension.toFixed(3));
    document.documentElement.style.setProperty("--master-audio-energy", audioEnergy.toFixed(3));
    window.MasterRenderPolicy?.recordFrame?.(now);
  }

  window.MASTER_FACE_WORLD = Object.freeze({
    load, update, spawnPulse, setSubjectForm, setSubjectFromText, setConversationSubject, restoreFaceSubject, inferSubjectForm
  });
  window.addEventListener("master:visual", (event) => {
    const detail = event.detail || {};
    const name = String(detail.name || detail.mode || "");
    if (/llm:|route:resolved|tool:call|pipeline:stage_start|fix_loop:pass_start/.test(name)) {
      const from = /tool|fetch|write|read/.test(name) ? "tools" : /fix|pipeline/.test(name) ? "lib" : "law";
      const to = from === "tools" ? "web" : from === "lib" ? "tools" : "lib";
      spawnPulse(from, to, Number(detail.activity || detail.confidence || 0.5));
    }
  }, { passive: true });
  window.addEventListener("master:bus", (event) => {
    const detail = event.detail || {};
    const type = String(detail.type || "");
    const payload = detail.payload || {};

    if (type === "turn:started") {
      clearSubjectRestoreTimer();
      return;
    }

    if (type === "speech:partial" || type === "speech:end" || type === "turn:committed") {
      const text = String(payload.transcript || payload.text || "").trim();
      if (text) setConversationSubject(text);
      if (type !== "speech:partial") scheduleFaceRestoration();
      return;
    }

    if (type === "turn:discarded" || type === "turn:interrupted") {
      restoreFaceSubject();
    }
  }, { passive: true });
  window.addEventListener("pagehide", () => {
    clearSubjectRestoreTimer();
    if (subjectTransitionTimer) clearTimeout(subjectTransitionTimer);
    subjectTransitionTimer = null;
    pendingSubjectForm = null;
  }, { once: true });
  window.addEventListener("master:face-ready", () => load(), { once: true });
  if (window._primerFired) load();
})();
