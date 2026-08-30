// Kinetic-depth renderer for ParticleKernel pools: raw gl.POINTS, no library.
//
// design_rules.kinetic_depth is the reason this file exists. Depth is implied
// by coherent motion, never by shaded surfaces — flat points that swing
// together read as one solid volume, and that reading needs one vertex buffer,
// a vertex shader that projects, and a fragment shader that colours. No scene
// graph, no material system, no mesh. cognition_ecology_render.js keeps drawing
// the same world through getContext("2d") beside this, so the flat path
// survives and the two can be compared frame for frame.
//
// Points carry depth in brightness rather than in size. FACE_POINT_IS_ONE_PIXEL
// and pixel_perfection's "gl_PointSize above 1.0" both forbid the size cue that
// kinetic_depth otherwise lists, because this canvas is a capped buffer that CSS
// upscales with image-rendering:pixelated: a fractional point size there is a
// blob, not a pixel. The remaining three cues — parallax under rotation,
// brightness and alpha falloff, and density — carry the volume, which is
// exactly how radio_brgen_tunnel.js does it, and kinetic_depth names that file
// the reference implementation.
(() => {
  "use strict";

  const VERT = `
precision highp float;
// x, y, z in face space; w is the cell's own weight (confidence x attention).
attribute vec4 aCell;
uniform vec2 uResolution;
uniform vec2 uCenter;
uniform float uYaw;
uniform float uPitch;
uniform float uFov;
uniform float uScale;
uniform float uDepth;
varying float vNear;
varying float vWeight;
void main() {
  vec3 p = aCell.xyz;

  // Yaw first, then a shallow pitch. Rotation is the whole effect: a point at
  // z = 0 barely moves while a point on the near face sweeps across the frame,
  // and that difference in travel is the parallax the eye reads as volume.
  float cy = cos(uYaw), sy = sin(uYaw);
  vec3 r = vec3(p.x * cy + p.z * sy, p.y, p.z * cy - p.x * sy);
  float cp = cos(uPitch), sp = sin(uPitch);
  r = vec3(r.x, r.y * cp - r.z * sp, r.y * sp + r.z * cp);

  // Guard the projection singularity at z = uFov so scale never blows up or
  // returns NaN for a cell that has drifted past the camera.
  float denom = max(0.35, uFov - r.z);
  float scale = uFov / denom;
  // y is not negated: the face's own pools store y growing downward — the mouth
  // sits at y 0.50 and the eyes at y 0.06 — and this renderer uses the same
  // convention so those pools can be drawn here without a sign flip.
  vec2 screen = r.xy * scale * uScale + uCenter;

  gl_Position = vec4(
    (screen.x / uResolution.x) * 2.0 - 1.0,
    1.0 - (screen.y / uResolution.y) * 2.0,
    0.0,
    1.0
  );
  // One point, one pixel. The buffer is small and CSS upscales it, so this
  // fragment is already a visible square block.
  gl_PointSize = 1.0;

  vNear = clamp((r.z + uDepth) / (2.0 * uDepth), 0.0, 1.0);
  vWeight = aCell.w;
}`;

  const FRAG = `
precision highp float;
uniform vec3 uInkFar;
uniform vec3 uInkNear;
uniform float uAlphaFar;
uniform float uAlphaNear;
uniform float uExposure;
varying float vNear;
varying float vWeight;
void main() {
  // Squared so the near half of the field pulls away from the far half faster
  // than distance alone would separate them. At one pixel there is no interior
  // to shape with gl_PointCoord, so falloff is the only modelling there is.
  float near = vNear * vNear;
  float alpha = mix(uAlphaFar, uAlphaNear, near) * vWeight * uExposure;
  gl_FragColor = vec4(mix(uInkFar, uInkNear, near), alpha);
}`;

  function compile(gl, type, source, label) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      const log = gl.getShaderInfoLog(shader);
      gl.deleteShader(shader);
      throw new Error(`face_points_gl: ${label} failed to compile: ${log}`);
    }
    return shader;
  }

  function link(gl, vertexSource, fragmentSource) {
    const program = gl.createProgram();
    gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, vertexSource, "vertex"));
    gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, fragmentSource, "fragment"));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      const log = gl.getProgramInfoLog(program);
      gl.deleteProgram(program);
      throw new Error(`face_points_gl: program failed to link: ${log}`);
    }
    return program;
  }

  // Skull cells come from the avatar's ink; tunnel cells are a sparse ring
  // field behind it. 700 + 400 stays under the 0.06 repulsion radius that
  // blew a 1400-cell shell apart.
  const SKULL = 700;
  const TUNNEL = 400;
  const CAPACITY = SKULL + TUNNEL;
  const FLOATS_PER_POINT = 4;
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

  const view = {
    yaw: 0,
    pitch: 0,
    // Activity opens the swing and drops the exposure back down when the face
    // goes quiet, so the volume is loudest exactly when something is happening.
    activity: 0.18,
    exposure: 1
  };

  let canvas = null;
  let gl = null;
  let program = null;
  let buffer = null;
  let uniform = {};
  let attribute = -1;
  let vertices = null;
  let pool = null;
  // Where each cell belongs, x/y/z interleaved and indexed exactly as the pool
  // is. It is a separate array rather than three more kernel fields because the
  // kernel's layout is shared with every other pool in the face and this is one
  // renderer's business.
  let home = null;
  let frameActive = false;
  let previous = performance.now();
  let internalW = 640;
  let internalH = 360;

  function kernel() {
    return window.ParticleKernel;
  }

  function makeCanvas() {
    const node = document.createElement("canvas");
    node.id = "face-points";
    node.setAttribute("aria-hidden", "true");
    node.style.cssText = [
      "position:fixed",
      "inset:0",
      "width:100vw",
      "height:100vh",
      "z-index:2",
      "pointer-events:none",
      "image-rendering:pixelated"
    ].join(";");
    document.body.appendChild(node);
    return node;
  }

  // The same budget the ecology canvas uses, and for the same reason: a capped
  // buffer taking the viewport's own aspect, so one fragment upscales to one
  // square block instead of a tall smear on a phone held upright.
  function resize() {
    const w = Math.max(1, innerWidth);
    const h = Math.max(1, innerHeight);
    const budget = (reducedMotion || (w * h) < 400000) ? 320 * 180 : 640 * 360;
    const aspect = Math.max(0.2, Math.min(5, w / h));
    const rows = Math.max(120, Math.round(Math.sqrt(budget / aspect)));
    internalW = Math.max(120, Math.round(rows * aspect));
    internalH = rows;
    canvas.width = internalW;
    canvas.height = internalH;
    if (gl) gl.viewport(0, 0, internalW, internalH);
  }

  // Ink of new_avatar.png (public/face_avatar.png): dark pixels become the
  // skull surface. The tunnel is the radio_brgen rings, laid behind that
  // mask rather than filling the viewport on their own.
  //
  // Era is the human-evolution axis this renderer exists to show. -1 is a
  // prognathic vault (ape), 0 is the avatar as drawn, +1 is a globular
  // cranium and a receding jaw — the trend from Australopithecus through
  // sapiens, continued. It breathes; it is not a slider.
  function eraAt(now) {
    return Math.sin(now * 0.00007);
  }

  function evolve(x, y, z, era) {
    const future = Math.max(0, era);
    const ape = Math.max(0, -era);
    const vault = 1 + future * 0.34;
    const jaw = 1 - future * 0.30 + ape * 0.18;
    const yScale = y < 0 ? vault : jaw;
    return [
      x * (1 + ape * 0.14),
      y * yScale,
      z * (1 + ape * 0.22) - ape * 0.12 + future * 0.08
    ];
  }

  function sampleAvatarInk(img) {
    const size = 96;
    const node = document.createElement("canvas");
    node.width = size;
    node.height = size;
    const ctx = node.getContext("2d");
    ctx.drawImage(img, 0, 0, size, size);
    const data = ctx.getImageData(0, 0, size, size).data;
    const ink = [];
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const i = (y * size + x) * 4;
        const lum = data[i] * 0.3 + data[i + 1] * 0.59 + data[i + 2] * 0.11;
        if (lum < 90) ink.push([(x + 0.5) / size, (y + 0.5) / size]);
      }
    }
    return ink;
  }

  function loadAvatar() {
    return new Promise((resolve) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => resolve(null);
      const paths = window.MASTER_ASSET_PATHS || {};
      img.src = paths.faceAvatar || "/face_avatar.png";
    });
  }

  // A hollow shell with an interior scatter. The shell gives the silhouette its
  // edge and the scatter fills it, so the field is densest where the volume is
  // deepest — density is the fourth depth cue and it is seeded here rather than
  // computed later.
  //
  // The cells do not decay. This field is a body rather than a burst: a cell
  // that dies leaves a hole in the silhouette, and refilling holes is a second
  // mechanism doing the job the first one broke.
  function seedVolume(img) {
    const K = kernel();
    if (!K) return;
    pool = K.createPool(CAPACITY);
    home = new Float32Array(CAPACITY * 3);
    const ink = img ? sampleAvatarInk(img) : [];
    for (let i = 0; i < SKULL; i++) {
      let x;
      let y;
      let z;
      if (ink.length) {
        const [u, v] = ink[i % ink.length];
        x = (u - 0.5) * 0.92;
        y = (v - 0.48) * 1.05;
        const r = Math.hypot(x, y);
        z = Math.sqrt(Math.max(0, 0.22 - r * r)) * (i % 3 === 0 ? -1 : 1);
      } else {
        const t = (i + 0.5) / SKULL;
        const phi = Math.acos(1 - 2 * t);
        const theta = Math.PI * (1 + Math.sqrt(5)) * i;
        const radius = i < SKULL * 0.62 ? 0.46 : 0.46 * Math.cbrt(Math.random());
        x = Math.sin(phi) * Math.cos(theta) * radius;
        y = Math.cos(phi) * radius * 1.18;
        z = Math.sin(phi) * Math.sin(theta) * radius;
      }
      home[i * 3] = x;
      home[i * 3 + 1] = y;
      home[i * 3 + 2] = z;
      K.spawn(pool, x, y, {
        z,
        confidence: 0.55 + Math.random() * 0.45,
        attention: 0.9,
        arousal: 0.2,
        decay: 1e-7
      });
    }
    // Warp-tunnel rings, the same FOV scroll radio_brgen_tunnel.js uses, parked
    // behind the skull so the mask reads as a creature looking down a throat.
    for (let i = 0; i < TUNNEL; i++) {
      const ring = Math.floor(i / 20);
      const ang = (i % 20) / 20 * Math.PI * 2;
      const z = -0.35 - ring * 0.11;
      const radius = 0.22 + ring * 0.03;
      const x = Math.cos(ang) * radius;
      const y = Math.sin(ang) * radius * 0.82;
      const idx = SKULL + i;
      home[idx * 3] = x;
      home[idx * 3 + 1] = y;
      home[idx * 3 + 2] = z;
      K.spawn(pool, x, y, {
        z,
        confidence: 0.35,
        attention: 0.4,
        arousal: 0.1,
        decay: 1e-7
      });
    }
  }

  // The pull back to home, applied after the kernel has stepped.
  //
  // Without it the field does not hold together for a second. MASTER_RUNTIME
  // ships spatial_repulsion_2d, which face_perf_guards turns on for every pool
  // unconditionally; 1400 cells inside a 0.46 shell are almost all within its
  // 0.06 radius, so they push each other apart and the ball becomes an even
  // scatter across the whole viewport — measured at a mean radius of 1.67 and a
  // maximum of 8.79 within ten seconds. A cell that knows where it belongs
  // turns that same repulsion into surface texture instead.
  const SPRING = 0.18;
  const MAX_WANDER = 0.34;

  function cohere() {
    const K = kernel();
    if (!K || !pool || !home) return;
    const F = K.FIELD;
    const stride = K.FIELDS_PER_CELL;
    for (let i = 0; i < pool.count; i++) {
      if (!pool.alive[i]) continue;
      const base = i * stride;
      const h = i * 3;
      const era = eraAt(previous);
      let hx = home[h];
      let hy = home[h + 1];
      let hz = home[h + 2];
      if (i < SKULL) {
        const evolved = evolve(hx, hy, hz, era);
        hx = evolved[0];
        hy = evolved[1];
        hz = evolved[2];
      } else {
        hz += ((previous * 0.00012) % 1.4) - 0.7;
      }
      let dx = pool.cells[base + F.x] - hx;
      let dy = pool.cells[base + F.y] - hy;
      let dz = pool.cells[base + F.z] - hz;
      dx *= 1 - SPRING;
      dy *= 1 - SPRING;
      dz *= 1 - SPRING;
      // The spring alone is an average, and an average lets one cell that
      // caught a hard shove keep going. The leash is what makes the silhouette
      // a promise rather than a tendency.
      const wander = Math.hypot(dx, dy, dz);
      if (wander > MAX_WANDER) {
        const scale = MAX_WANDER / wander;
        dx *= scale;
        dy *= scale;
        dz *= scale;
        pool.cells[base + F.vx] *= 0.4;
        pool.cells[base + F.vy] *= 0.4;
        pool.cells[base + F.vz] *= 0.4;
      }
      pool.cells[base + F.x] = hx + dx;
      pool.cells[base + F.y] = hy + dy;
      pool.cells[base + F.z] = hz + dz;
    }
  }

  // An event pushes cells outward along their own radius and gives them a vz,
  // which is what makes the depth axis semantic rather than decorative: the
  // volume swells toward the viewer when the runtime is working.
  function ingest(detail = {}) {
    const K = kernel();
    if (!K || !pool) return;
    const F = K.FIELD;
    const stride = K.FIELDS_PER_CELL;
    const entropy = Number.isFinite(detail.entropy) ? detail.entropy : 0.2;
    const force = 0.0012 + entropy * 0.0024;
    view.activity = Math.min(1, view.activity + 0.28);
    for (let i = 0; i < pool.count; i++) {
      if (!pool.alive[i]) continue;
      const base = i * stride;
      const x = pool.cells[base + F.x];
      const y = pool.cells[base + F.y];
      const z = pool.cells[base + F.z];
      const length = Math.max(0.02, Math.hypot(x, y, z));
      pool.cells[base + F.vx] += (x / length) * force;
      pool.cells[base + F.vy] += (y / length) * force;
      pool.cells[base + F.vz] += (z / length) * force;
      pool.cells[base + F.attention] = Math.min(1, pool.cells[base + F.attention] + 0.2);
    }
  }

  // Every pool drawn this frame. Only this file's own volume so far.
  //
  // window.mouthPool and window.eyePool are the obvious next entries — they are
  // ParticleKernel pools in the same coordinate convention, and at z = 0 they
  // would sit on the focal plane and hold still while the volume swings past
  // them, which is the parallax made literal. What is not yet established is
  // the scale that puts them on top of the THREE mask they belong to rather
  // than beside it, and drawing them at a guessed scale would be a second face
  // in the wrong place.
  function drawList() {
    return pool ? [pool] : [];
  }

  function fill(pools) {
    const K = kernel();
    const F = K.FIELD;
    const stride = K.FIELDS_PER_CELL;
    let written = 0;
    for (const p of pools) {
      for (let i = 0; i < p.count && written < CAPACITY; i++) {
        if (!p.alive[i]) continue;
        const base = i * stride;
        const out = written * FLOATS_PER_POINT;
        vertices[out] = p.cells[base + F.x];
        vertices[out + 1] = p.cells[base + F.y];
        vertices[out + 2] = p.cells[base + F.z];
        const confidence = Math.max(0, Math.min(1, p.cells[base + F.confidence]));
        const attention = Math.max(0, Math.min(1, p.cells[base + F.attention]));
        vertices[out + 3] = 0.35 + confidence * 0.45 + attention * 0.2;
        written++;
      }
    }
    return written;
  }

  function initGL() {
    // The primer gate (chat/index.html.erb) returns null from getContext for
    // any webgl request until the tap fires. That gate is deliberate, so this
    // asks once and simply does not draw if the answer is no — a renderer that
    // retried around it would be defeating it.
    const options = { alpha: true, antialias: false, depth: false, premultipliedAlpha: false };
    gl = canvas.getContext("webgl", options) || canvas.getContext("experimental-webgl", options);
    if (!gl) return false;
    program = link(gl, VERT, FRAG);
    attribute = gl.getAttribLocation(program, "aCell");
    for (const name of [
      "uResolution", "uCenter", "uYaw", "uPitch", "uFov", "uScale", "uDepth",
      "uInkFar", "uInkNear", "uAlphaFar", "uAlphaNear", "uExposure"
    ]) {
      uniform[name] = gl.getUniformLocation(program, name);
    }
    vertices = new Float32Array(CAPACITY * FLOATS_PER_POINT);
    buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, vertices.byteLength, gl.DYNAMIC_DRAW);
    gl.disable(gl.DEPTH_TEST);
    gl.enable(gl.BLEND);
    // Straight alpha, not additive. An additive pass over a point cloud is the
    // WebGL spelling of a soft glow, which NO_WEBGL_GLOW_PASS forbids.
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.clearColor(0, 0, 0, 0);
    return true;
  }

  function frame(now) {
    if (document.hidden) {
      frameActive = false;
      previous = now;
      return;
    }
    const K = kernel();
    const dt = Math.min(48, now - previous);
    previous = now;

    view.activity += (0.16 - view.activity) * 0.006;
    const swing = reducedMotion ? 0.06 : 0.34 + view.activity * 0.26;
    // A full turn would present the shell's back, which is the same shell. A
    // swing shows both profiles and keeps the near face near, where the
    // brightness falloff has something to say.
    view.yaw = Math.sin(now * 0.00019) * swing;
    view.pitch = Math.sin(now * 0.00011) * (reducedMotion ? 0.02 : 0.09);

    if (K && pool) {
      K.step(pool, dt / 16.67, { entropy: 0.14, confidence: 0.86, decayScale: 1 });
      cohere();
    }

    const speaking = document.body?.dataset.mode === "speaking";
    const focusMode = document.body?.dataset.focusMode === "1";
    let exposure = focusMode ? 0.2 : 1;
    if (speaking) exposure *= 0.55;
    if (document.body?.dataset.longSilence === "1") exposure *= 0.6;
    view.exposure = exposure;

    const pools = drawList();
    const count = K ? fill(pools) : 0;

    gl.viewport(0, 0, internalW, internalH);
    gl.clear(gl.COLOR_BUFFER_BIT);
    if (count > 0) {
      gl.useProgram(program);
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
      gl.bufferSubData(gl.ARRAY_BUFFER, 0, vertices.subarray(0, count * FLOATS_PER_POINT));
      gl.enableVertexAttribArray(attribute);
      gl.vertexAttribPointer(attribute, 4, gl.FLOAT, false, 0, 0);
      gl.uniform2f(uniform.uResolution, internalW, internalH);
      gl.uniform2f(uniform.uCenter, internalW * 0.5, internalH * 0.48);
      gl.uniform1f(uniform.uYaw, view.yaw);
      gl.uniform1f(uniform.uPitch, view.pitch);
      gl.uniform1f(uniform.uFov, 2.6);
      const fill = document.body?.dataset.portrait === "1" ? 0.58 : 0.30;
      gl.uniform1f(uniform.uScale, Math.min(internalW, internalH) * fill);
      gl.uniform1f(uniform.uDepth, 0.6);
      // The face's own ink: bone-warm near, cooled and dimmed toward the back.
      gl.uniform3f(uniform.uInkFar, 0.42, 0.40, 0.36);
      gl.uniform3f(uniform.uInkNear, 0.92, 0.88, 0.78);
      gl.uniform1f(uniform.uAlphaFar, 0.06);
      gl.uniform1f(uniform.uAlphaNear, 0.88);
      gl.uniform1f(uniform.uExposure, view.exposure);
      gl.drawArrays(gl.POINTS, 0, count);
    }

    requestAnimationFrame(frame);
  }

  function ensureFrame() {
    if (frameActive || document.hidden || !gl) return;
    frameActive = true;
    previous = performance.now();
    requestAnimationFrame(frame);
  }

  function boot(img) {
    if (!kernel()) return;
    canvas = document.getElementById("face-points") ?? makeCanvas();
    resize();
    if (!initGL()) return;
    resize();
    seedVolume(img);
    window.addEventListener("resize", resize, { passive: true });
    window.addEventListener("master:visual", (event) => ingest(event?.detail ?? {}), { passive: true });
    document.addEventListener("visibilitychange", () => { if (!document.hidden) ensureFrame(); }, { passive: true });
    window.MASTERFacePoints = {
      get canvas() { return canvas; },
      get pool() { return pool; },
      get pointCount() { return drawList().reduce((sum, p) => sum + p.count, 0); },
      view
    };
    ensureFrame();
  }

  loadAvatar().then(boot);
})();
