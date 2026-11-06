// The web face in plain ASCII: the same drawing the terminal makes
// (MASTER/lib/cli/face/ascii.rb), ported step for step. Every tunable is read from
// the face contract (MASTER/data/tokens.yml, face_interface), which the page hands
// over as window.MASTER_FACE_CONTRACT; nothing here restates a number.
//
// The head is not sent as data. Face::Head places a hex lattice over the painted
// depth map (Face::DepthMap) and wraps it round a head; both are small, so this file
// carries the same arithmetic and reproduces the points to the last bit, which
// test/face_ascii.test.mjs holds against MASTER/test/fixtures/face_ascii_frames.json.
//
// A frame is a pure function of the points, the size and the Look. No randomness,
// every cell index is a floor, rounding is floor(x + 0.5), and the one place Ruby
// differs from naive arithmetic is Array#sum, which is Kahan-Babuska compensated
// (kbSum below): the anchors are means, and a plain loop moves them by a cell.
//
// Printable ASCII only. Braille is retired.
(function (root) {
  "use strict";

  // Face::FPS in the terminal; the mouth's timed level steps this many times a second.
  const FPS = 20;
  const NONE = -1.0e9;
  const LIVE = NONE / 2;

  const num = (value, fallback) => (typeof value === "number" && Number.isFinite(value) ? value : fallback);
  const clamp = (value, lo, hi) => Math.min(Math.max(value, lo), hi);
  const halfUp = (value) => Math.floor(value + 0.5);
  const half = (n) => Math.floor(n / 2);
  const hypot = (a, b) => Math.sqrt(a * a + b * b);
  // Ruby's Float#%: fmod, moved into the divisor's sign. Exact, unlike a - floor(a / b) * b.
  const mod = (a, b) => {
    const r = a % b;
    return r !== 0 && (r < 0) !== (b < 0) ? r + b : r;
  };

  // Ruby's Array#sum over floats: Kahan-Babuska, starting from zero.
  function kbSum(values) {
    let f = 0.0;
    let c = 0.0;
    for (let i = 0; i < values.length; i += 1) {
      const x = values[i];
      const t = f + x;
      if (Math.abs(f) >= Math.abs(x)) c += (f - t) + x;
      else c += (x - t) + f;
      f = t;
    }
    return f + c;
  }

  // Ruby's min_by and max_by keep the first of equal elements.
  function minBy(list, key) {
    let best = null;
    let bestKey = 0;
    for (let i = 0; i < list.length; i += 1) {
      const k = key(list[i]);
      if (best === null || k < bestKey) { best = list[i]; bestKey = k; }
    }
    return best;
  }

  function maxBy(list, key) {
    let best = null;
    let bestKey = 0;
    for (let i = 0; i < list.length; i += 1) {
      const k = key(list[i]);
      if (best === null || k > bestKey) { best = list[i]; bestKey = k; }
    }
    return best;
  }

  function minMax(values) {
    let lo = values[0];
    let hi = values[0];
    for (let i = 1; i < values.length; i += 1) {
      if (values[i] < lo) lo = values[i];
      if (values[i] > hi) hi = values[i];
    }
    return [lo, hi];
  }

  function build(contract) {
    const ascii = (contract?.ascii) || {};
    const morphology = (contract?.spatial?.morphology) || {};
    if (!ascii.dither || !ascii.motion) throw new Error("face contract has no ascii block");

    // ---- Face::Glyphs -------------------------------------------------------
    const ASPECT = num(ascii.aspect, 2.0);
    const DITHER = ascii.dither;
    const DITHER_GAIN = ascii.dither_gain;
    const INK = ascii.ink || {};
    const DEFAULT_CHARS = ascii.chars || " .:-=+*#%@";
    const SLASH = Math.atan(ASPECT);
    const FLAT = SLASH / 2;
    const STEEP = (SLASH + Math.PI / 2) / 2;
    const UPRIGHT = Math.PI - STEEP;
    const CEILING_ANGLE = Math.PI - FLAT;

    // The glyph for a line running along (dx, dy) with y up, in square sub-pixels.
    function line(dx, dy) {
      let angle = Math.atan2(dy, dx);
      if (angle < 0) angle += Math.PI;
      if (angle < FLAT || angle >= CEILING_ANGLE) return "-";
      if (angle < STEEP) return "/";
      if (angle < UPRIGHT) return "|";
      return "\\";
    }

    // A horizontal edge placed by the sub-row it falls on.
    function level(top, bottom, openBelow) {
      if (!(top && bottom)) return "-";
      return openBelow ? "_" : "'";
    }

    function ramp(chars, mode) {
      let glyphs = Array.from(String(chars === undefined || chars === null ? DEFAULT_CHARS : chars));
      if (glyphs.length < 2) glyphs = [" ", "#"];
      return String(mode || ascii.mode) === "light" ? glyphs.reverse() : glyphs;
    }

    // Each ramp glyph's place in ink space, 0 to 1, in the order the ramp is drawn; a glyph
    // without a measurement takes an even step. Light mode mirrors the scale.
    function levels(glyphs, mode) {
      const light = String(mode || ascii.mode) === "light";
      const dark = light ? glyphs.slice().reverse() : glyphs;
      let top = 0.0;
      dark.forEach((g) => { const v = Object.prototype.hasOwnProperty.call(INK, g) ? INK[g] : 0.0; if (v > top) top = v; });
      if (!(top > 0.0)) top = 1.0;
      const step = 1.0 / Math.max(dark.length - 1, 1);
      const scale = dark.map((g, i) => (Object.prototype.hasOwnProperty.call(INK, g) ? INK[g] / top : i * step));
      return light ? scale.reverse().map((v) => 1.0 - v) : scale;
    }

    // The ramp index for a tone in ink space: of the two glyphs whose ink brackets the tone, the
    // denser when the tone's share of the gap beats the integer Bayer threshold fixed in screen space.
    function index(tone, lv, col, row) {
      const last = lv.length - 1;
      if (tone <= lv[0]) return 0;
      if (tone >= lv[last]) return last;
      let lo = 0;
      while (lv[lo + 1] <= tone) lo += 1;
      const share = (tone - lv[lo]) / (lv[lo + 1] - lv[lo]);
      const threshold = 0.5 + ((((DITHER[row % 4][col % 4] + 0.5) / 16.0) - 0.5) * DITHER_GAIN);
      return share > threshold ? lo + 1 : lo;
    }

    // ---- Face::DepthMap -----------------------------------------------------
    // web/public/face.part1.txt's generateFaceDepthMap, layer for layer.
    const CX = 0.493;
    const CY = 0.46;
    const FADE = [1.0, 0, 0.0];
    const radial = (x, y, r, stops, rest) => Object.assign({ radial: [x, y, x, y, r], stops }, rest || {});
    const LAYERS = [
      { radial: [CX, CY - 0.10, CX, CY, 0.36], ellipse: [CX, CY, 0.255, 0.48],
        stops: [[0, 228, 1.0], [0.34, 182, 1.0], [0.70, 72, 1.0], [1.0, 0, 1.0]] },
      ...[-0.215, 0.215].map((ex) => radial(CX + ex, CY + 0.28, 0.16, [[0, 0, 0.98], [0.5, 0, 0.72], FADE])),
      radial(CX, CY - 0.36, 0.30, [[0, 210, 0.78], [0.55, 150, 0.36], FADE]),
      radial(CX, CY - 0.44, 0.18, [[0, 198, 0.55], [0.62, 118, 0.18], FADE]),
      ...[-0.20, 0.20].map((ex) => radial(CX + ex, CY - 0.28, 0.09, [[0, 0, 0.28], FADE])),
      ...[-0.112, 0.112].map((ex) => ({
        linear: [CX + ex - 0.08, CY - 0.198, CX + ex + 0.08, CY - 0.186],
        rect: [CX + ex - 0.08, CY - 0.206, 0.16, 0.014], stops: [[0, 0, 0.0], [0.5, 0, 0.08], FADE],
      })),
      ...[-0.112, 0.112].map((ex) => radial(CX + ex, CY - 0.168, 0.078, [[0, 205, 0.38], [0.5, 150, 0.16], FADE])),
      radial(CX, CY - 0.160, 0.022, [[0, 0, 0.22], FADE]),
      ...[[-0.118, 0.66], [0.118, 0.62]].map(([ex, alpha]) =>
        radial(0.0, 0.0, 0.106, [[0, 0, alpha], [0.45, 0, 0.70], [0.80, 0, 0.24], FADE],
          { transform: [CX + ex, CY - 0.088, 1.42, 1.08], ellipse: [0.0, 0.0, 0.106, 0.106] })),
      ...[-0.118, 0.118].flatMap((ex) => [
        radial(CX + ex, CY - 0.088, 0.044, [[0, 185, 0.42], [0.55, 95, 0.18], FADE]),
        radial(CX + ex + 0.012, CY - 0.102, 0.028, [[0, 240, 0.78], [0.45, 190, 0.30], FADE]),
      ]),
      { linear: [CX - 0.012, 0, CX + 0.012, 0], rect: [CX - 0.012, CY - 0.02, 0.024, 0.12],
        stops: [[0, 0, 0.0], [0.5, 205, 0.52], FADE] },
      radial(CX, CY + 0.082, 0.058, [[0, 245, 0.92], [0.30, 220, 0.68], [0.62, 150, 0.30], FADE]),
      ...[-0.048, 0.048].map((ex) => radial(CX + ex, CY + 0.100, 0.022, [[0, 0, 0.32], FADE])),
      ...[-0.188, 0.188].map((ex) => radial(CX + ex, CY + 0.012, 0.098, [[0, 190, 0.38], [0.6, 100, 0.14], FADE])),
      ...[-0.068, 0.068].map((ex) => radial(CX + ex, CY + 0.142, 0.042, [[0, 0, 0.22], [0.6, 0, 0.08], FADE])),
      radial(CX, CY + 0.158, 0.018, [[0, 0, 0.26], FADE]),
      radial(0.0, 0.0, 0.050, [[0, 215, 0.78], [0.38, 168, 0.42], FADE],
        { transform: [CX, CY + 0.198, 1.85, 1.0], ellipse: [0.0, 0.0, 0.050, 0.050] }),
      radial(0.0, 0.0, 0.056, [[0, 205, 0.72], [0.38, 158, 0.38], FADE],
        { transform: [CX, CY + 0.212, 1.95, 1.0], ellipse: [0.0, 0.0, 0.056, 0.056] }),
      { linear: [CX - 0.062, 0, CX + 0.062, 0], rect: [CX - 0.062, CY + 0.206, 0.124, 0.007],
        stops: [[0, 0, 0.0], [0.10, 0, 0.34], [0.5, 0, 0.42], [0.90, 0, 0.34], FADE] },
      radial(CX, CY + 0.238, 0.022, [[0, 0, 0.30], FADE]),
      radial(CX, CY + 0.318, 0.068, [[0, 155, 0.52], [0.58, 82, 0.20], FADE]),
      ...[-0.36, 0.36].map((ex) => ({ radial: [CX + ex, CY - 0.04, CX + ex, CY + 0.04, 0.048], stops: [[0, 90, 0.10], FADE] })),
      { linear: [0, CY + 0.44, 0, 1.0], rect: [CX - 0.032, CY + 0.44, 0.064, 1.0 - (CY + 0.44)],
        stops: [[0, 58, 0.30], FADE] },
    ];

    // The canvas's two-circle radial gradient with a start radius of zero: the largest
    // t for which the point lies on the circle interpolated between focus and end.
    function quadratic(a, b, c) {
      if (Math.abs(a) < 1e-12) {
        if (b === 0 || (-c / b) < 0) return null;
        return -c / b;
      }
      const disc = (b * b) - (4 * a * c);
      if (disc < 0) return null;
      const r1 = (-b + Math.sqrt(disc)) / (2 * a);
      const r2 = (-b - Math.sqrt(disc)) / (2 * a);
      const roots = [r1, r2].filter((t) => t >= 0);
      return roots.length ? Math.max(...roots) : null;
    }

    function radiusT(spec, x, y) {
      const fx = spec[0], fy = spec[1], ex = spec[2], ey = spec[3], r = spec[4];
      const dx = ex - fx;
      const dy = ey - fy;
      const qx = x - fx;
      const qy = y - fy;
      const a = (dx * dx) + (dy * dy) - (r * r);
      const b = -2 * ((qx * dx) + (qy * dy));
      const c = (qx * qx) + (qy * qy);
      return quadratic(a, b, c);
    }

    function along(spec, x, y) {
      const x0 = spec[0], y0 = spec[1], x1 = spec[2], y1 = spec[3];
      const dx = x1 - x0;
      const dy = y1 - y0;
      return (((x - x0) * dx) + ((y - y0) * dy)) / ((dx * dx) + (dy * dy));
    }

    function stop(stops, t) {
      let upper = stops.findIndex((s) => s[0] >= t);
      if (upper < 0) upper = stops.length - 1;
      if (upper === 0) return [stops[0][1], stops[0][2]];
      const s0 = stops[upper - 1];
      const s1 = stops[upper];
      const f = s1[0] === s0[0] ? 0.0 : (t - s0[0]) / (s1[0] - s0[0]);
      return [s0[1] + ((s1[1] - s0[1]) * f), s0[2] + ((s1[2] - s0[2]) * f)];
    }

    function paint(layer, u, v, under) {
      const tr = layer.transform;
      const x = tr ? (u - tr[0]) / tr[2] : u;
      const y = tr ? (v - tr[1]) / tr[3] : v;
      if (layer.ellipse) {
        const e = layer.ellipse;
        const dx = (x - e[0]) / e[2];
        const dy = (y - e[1]) / e[3];
        if (!((dx * dx) + (dy * dy) <= 1.0)) return under;
      } else if (layer.rect) {
        const r = layer.rect;
        if (!(x >= r[0] && x <= r[0] + r[2] && y >= r[1] && y <= r[1] + r[3])) return under;
      }
      const t = layer.linear ? along(layer.linear, x, y) : radiusT(layer.radial, x, y);
      if (t === null) return under;
      const gs = stop(layer.stops, clamp(t, 0.0, 1.0));
      return (gs[0] * gs[1]) + (under * (1 - gs[1]));
    }

    // Brightness at u, v in 0..1, from 0.0 (black) to 1.0.
    function lum(u, v) {
      let under = 0.0;
      for (let i = 0; i < LAYERS.length; i += 1) under = paint(LAYERS[i], u, v, under);
      return under / 255.0;
    }

    // ---- Face::Head ---------------------------------------------------------
    const SPREAD = 0.62;
    const m = (key, fallback) => num(morphology[key], fallback);
    const CRANIUM_SCALE = m("cranium_scale", 1.18);
    const CRANIAL_WIDTH = m("cranial_width", 1.06);
    const UPPER_FACE_SCALE = m("upper_face_scale", 0.96);
    const LOWER_FACE_SCALE = m("lower_face_scale", 0.80);
    const FACIAL_VERTICALIZATION = m("facial_verticalization", 1.04);
    const MASTICATORY_SCALE = m("masticatory_scale", 0.78);
    const ORBITAL_SCALE = m("orbital_scale", 1.10);
    const ORBITAL_VERTICAL_SCALE = m("orbital_vertical_scale", 1.06);
    const NOSE_SCALE = m("nose_scale", 0.86);
    const NASAL_PROJECTION = m("nasal_projection", NOSE_SCALE);
    const JAW_PROJECTION = m("jaw_projection", 0.80);
    const JAW_SOFTENING = m("jaw_softening", 0.92);
    const PUPIL_SCALE = m("pupil_scale", 0.88);
    const ASYMMETRY = m("asymmetry", 0.010);
    const ASYMMETRY_SEED = Math.trunc(m("asymmetry_seed", 73421));
    const GENERATION = m("generation", 0);
    const EYES = [-1, 1].map((side) => {
      const bias = Math.sin((ASYMMETRY_SEED * 0.0001) + (side * 17.17) + GENERATION * 0.71);
      const ex = (0.118 * ORBITAL_SCALE * side) + (side * ASYMMETRY * bias * 0.12);
      return [(((CX + ex) * 2) - 1) * SPREAD, -(((((CY - 0.088) * 2) - 1)) * SPREAD)];
    });
    const SOCKET = [0.187 * ORBITAL_SCALE, 0.142 * ORBITAL_SCALE * ORBITAL_VERTICAL_SCALE];
    const PUPIL = 0.07 * PUPIL_SCALE;
    const MOUTH = [((CX * 2) - 1) * SPREAD, -(((((CY + 0.205) * 2) - 1)) * SPREAD)];
    const MOUTH_REACH = 0.14 * LOWER_FACE_SCALE * m("mouth_scale", 0.84);
    const SKIN_ZONE = 0;
    const EYE_ZONE = 1;
    const PUPIL_ZONE = 2;
    const MOUTH_ZONE = 3;

    function zoneAt(x, y) {
      if (hypot(x - MOUTH[0], y - MOUTH[1]) < MOUTH_REACH) return MOUTH_ZONE;
      let eye = null;
      for (let i = 0; i < EYES.length; i += 1) {
        const dx = (x - EYES[i][0]) / SOCKET[0];
        const dy = (y - EYES[i][1]) / SOCKET[1];
        if ((dx * dx) + (dy * dy) <= 1.0) { eye = EYES[i]; break; }
      }
      if (!eye) return SKIN_ZONE;
      return hypot(x - eye[0], y - eye[1]) < PUPIL ? PUPIL_ZONE : EYE_ZONE;
    }

    // ---- Face::Masks --------------------------------------------------------
    // The mask morph targets: numbers laid over the head's morphology, blended by
    // smoothstep, on the head's own lattice. All of them are in the contract.
    const MASKS = ascii.masks || {};
    const MASK_ORDER = MASKS.order || [];
    const MASK_TRIGGERS = MASKS.trigger_states || [];
    const MASK_EASE = MASKS.ease || { in: 1.2, out: 0.8 };
    const MASK_TAKEOVER = num(MASKS.takeover, 0.5);
    const BEAK_MIN = num(MASKS.beak_min, 0.015);
    const BROW_MIN = num(MASKS.brow_min, 0.03);
    const MOUTH_SLACK = num(MASKS.mouth_slack, 0.0);
    const RING_MIN_PX = num(MASKS.ring_min_px, 1.0);
    const MASK_GLYPHS = MASKS.glyphs || {};
    const NEUTRAL = Object.assign({
      cranium_scale: CRANIUM_SCALE,
      cranial_width: CRANIAL_WIDTH,
      upper_face_scale: UPPER_FACE_SCALE,
      lower_face_scale: LOWER_FACE_SCALE,
      facial_verticalization: FACIAL_VERTICALIZATION,
      jaw_projection: JAW_PROJECTION,
      jaw_softening: JAW_SOFTENING,
      masticatory_scale: MASTICATORY_SCALE,
      nasal_projection: NASAL_PROJECTION,
    }, MASKS.neutral || {});

    function smoothstep(s) {
      const c = clamp(s, 0.0, 1.0);
      return c * c * (3.0 - (2.0 * c));
    }

    // The parameters of a target, or the human head's when name is null.
    function maskParams(name) {
      if (name === null || name === undefined) return NEUTRAL;
      const target = (MASKS.targets || {})[name];
      if (!target) throw new Error(`masks: no target ${name}`);
      Object.keys(target).forEach((key) => { if (!(key in NEUTRAL)) throw new Error(`masks: ${name} sets unknown key ${key}`); });
      return Object.assign({}, NEUTRAL, target);
    }

    // Parameter-wise interpolation by smoothstep; the ends are exact.
    function morph(from, to, s) {
      if (s <= 0.0) return from;
      if (s >= 1.0) return to;
      const e = smoothstep(s);
      const out = {};
      Object.keys(from).forEach((key) => { out[key] = from[key] + ((to[key] - from[key]) * e); });
      return out;
    }

    // How far toward the mask the face is at time t, linear, 0 to 1.
    function maskMix(state, t, since, from) {
      const trigger = MASK_TRIGGERS.indexOf(String(state)) >= 0;
      const span = trigger ? MASK_EASE.in : MASK_EASE.out;
      const progress = span > 0 ? clamp((t - since) / span, 0.0, 1.0) : 1.0;
      const start = from === undefined ? 0.0 : from;
      return start + (((trigger ? 1.0 : 0.0) - start) * progress);
    }

    // The mask a session wears: FNV-1a over its id's UTF-8 bytes.
    function pickMask(session) {
      let id = session === undefined || session === null ? "" : String(session);
      if (id === "") id = MASKS.default_session || "master";
      const bytes = new TextEncoder().encode(id);
      let h = 2166136261;
      for (let i = 0; i < bytes.length; i += 1) h = Math.imul(h ^ bytes[i], 16777619) >>> 0;
      return MASK_ORDER[h % MASK_ORDER.length];
    }


    // ---- Face::Mesh ---------------------------------------------------------
    // An indexed triangle mesh, outward wound: flat arrays of positions, vertex brightness
    // and triangle corners, with the landmarks and mask numbers a head carries.
    const CAVITY_GAIN = ascii.cavity.gain;
    const MESH_BRIGHTNESS = 0.8;

    function blend(a, b, e) {
      if (Array.isArray(a)) return a.map((v, i) => blend(v, b[i], e));
      if (a !== null && typeof a === "object") {
        const out = {};
        Object.keys(a).forEach((k) => { out[k] = blend(a[k], b[k], e); });
        return out;
      }
      return a + ((b - a) * e);
    }

    class Mesh {
      constructor(pos, tris, bright, opts) {
        const o = opts || {};
        this.pos = pos;
        this.tris = tris;
        this.bright = bright;
        this.landmarks = o.landmarks || null;
        this.params = o.params || null;
        this.margins = o.margins || [0.0, 0.0];
        this.cachedBounds = null;
        this.cachedNormals = null;
        this.cachedCavity = null;
      }

      mesh() { return this; }

      get vertexCount() { return this.pos.length / 3; }

      get triangleCount() { return this.tris.length / 3; }

      // The vertices of a and b blended by e, on a's triangles; the landmarks and margins
      // follow, the numbers are the caller's.
      static morph(a, b, e, params) {
        const pos = a.pos.map((v, i) => v + ((b.pos[i] - v) * e));
        const bright = a.bright.map((v, i) => v + ((b.bright[i] - v) * e));
        return new Mesh(pos, a.tris, bright, { landmarks: blend(a.landmarks, b.landmarks, e), params, margins: blend(a.margins, b.margins, e) });
      }

      // [xmin, xmax, ymin, ymax, reach]: the box in x and y and the largest hypot(x, z).
      bounds() {
        if (this.cachedBounds) return this.cachedBounds;
        const pos = this.pos;
        let xlo = Infinity; let xhi = -Infinity; let ylo = Infinity; let yhi = -Infinity; let reach = 0.0;
        for (let i = 0; i < pos.length; i += 3) {
          const x = pos[i]; const y = pos[i + 1];
          if (x < xlo) xlo = x;
          if (x > xhi) xhi = x;
          if (y < ylo) ylo = y;
          if (y > yhi) yhi = y;
          const d = Math.sqrt((x * x) + (pos[i + 2] * pos[i + 2]));
          if (d > reach) reach = d;
        }
        this.cachedBounds = [xlo, xhi, ylo, yhi, reach];
        return this.cachedBounds;
      }

      // The face normal (unnormalised, twice the area) of a corner triple.
      face(a, b, c) {
        const p = this.pos;
        const ux = p[b] - p[a]; const uy = p[b + 1] - p[a + 1]; const uz = p[b + 2] - p[a + 2];
        const vx = p[c] - p[a]; const vy = p[c + 1] - p[a + 1]; const vz = p[c + 2] - p[a + 2];
        return [(uy * vz) - (uz * vy), (uz * vx) - (ux * vz), (ux * vy) - (uy * vx)];
      }

      // Unit vertex normals: the area-weighted mean of the faces round each.
      normals() {
        if (this.cachedNormals) return this.cachedNormals;
        const n = new Array(this.pos.length).fill(0.0);
        const t = this.tris;
        for (let i = 0; i < t.length; i += 3) {
          const a = t[i] * 3; const b = t[i + 1] * 3; const c = t[i + 2] * 3;
          const f = this.face(a, b, c);
          [a, b, c].forEach((v) => { n[v] += f[0]; n[v + 1] += f[1]; n[v + 2] += f[2]; });
        }
        for (let i = 0; i < n.length; i += 3) {
          let len = Math.sqrt((n[i] * n[i]) + (n[i + 1] * n[i + 1]) + (n[i + 2] * n[i + 2]));
          if (len === 0) len = 1.0;
          n[i] /= len; n[i + 1] /= len; n[i + 2] /= len;
        }
        this.cachedNormals = n;
        return n;
      }

      // 0..1 per vertex: how far the neighbours' mean stands out along the normal, over the
      // squared edge length, times the contract's gain.
      cavity() {
        if (this.cachedCavity) return this.cachedCavity;
        const count = this.vertexCount;
        const p = this.pos;
        const sums = new Array(p.length).fill(0.0);
        const deg = new Array(count).fill(0);
        const edge2 = new Array(count).fill(0.0);
        const dist2 = (a, b) => ((p[a] - p[b]) * (p[a] - p[b])) + ((p[a + 1] - p[b + 1]) * (p[a + 1] - p[b + 1])) + ((p[a + 2] - p[b + 2]) * (p[a + 2] - p[b + 2]));
        const t = this.tris;
        for (let i = 0; i < t.length; i += 3) {
          const a = t[i] * 3; const b = t[i + 1] * 3; const c = t[i + 2] * 3;
          [[a, b, c], [b, c, a], [c, a, b]].forEach(([v, u, w]) => {
            for (let k = 0; k < 3; k += 1) sums[v + k] += p[u + k] + p[w + k];
            deg[v / 3] += 2;
            edge2[v / 3] += dist2(v, u) + dist2(v, w);
          });
        }
        const n = this.normals();
        const out = new Array(count);
        for (let v = 0; v < count; v += 1) {
          const d = deg[v];
          if (d === 0) { out[v] = 0.0; continue; }
          let o = 0.0;
          for (let k = 0; k < 3; k += 1) o += ((sums[(3 * v) + k] / d) - p[(3 * v) + k]) * n[(3 * v) + k];
          out[v] = clamp(CAVITY_GAIN * o / (edge2[v] / d), 0.0, 1.0);
        }
        this.cachedCavity = out;
        return out;
      }

      // Six times the enclosed volume; positive when the winding is outward.
      volume() {
        const p = this.pos;
        const t = this.tris;
        let sum = 0.0;
        for (let i = 0; i < t.length; i += 3) {
          const a = t[i] * 3; const b = t[i + 1] * 3; const c = t[i + 2] * 3;
          sum += (p[a] * ((p[b + 1] * p[c + 2]) - (p[b + 2] * p[c + 1])))
            - (p[a + 1] * ((p[b] * p[c + 2]) - (p[b + 2] * p[c])))
            + (p[a + 2] * ((p[b] * p[c + 1]) - (p[b + 1] * p[c])));
        }
        return sum;
      }
    }

    function meshStl(text) {
      const re = /^\s*vertex\s+(\S+)\s+(\S+)\s+(\S+)/gim;
      const verts = [];
      let hit;
      while ((hit = re.exec(text)) !== null) verts.push([hit[1], hit[2], hit[3]].map(parseFloat));
      const triangles = [];
      for (let i = 0; i + 2 < verts.length; i += 3) triangles.push([verts[i], verts[i + 1], verts[i + 2]]);
      return triangles;
    }

    function meshObj(text) {
      const verts = [];
      const vre = /^v\s+(\S+)\s+(\S+)\s+(\S+)/gm;
      let hit;
      while ((hit = vre.exec(text)) !== null) verts.push([hit[1], hit[2], hit[3]].map(parseFloat));
      const triangles = [];
      const fre = /^f\s+(.+)$/gm;
      while ((hit = fre.exec(text)) !== null) {
        const ids = hit[1].trim().split(/\s+/).map((ref) => {
          const i = parseInt(ref.split("/")[0], 10) || 0;
          return i < 0 ? verts.length + i : i - 1;
        });
        for (let k = 1; k < ids.length - 1; k += 1) triangles.push([verts[ids[0]], verts[ids[k]], verts[ids[k + 1]]]);
      }
      return triangles;
    }

    // An ASCII STL or an OBJ read into a flat-shaded mesh, centred on its bounding box; y is
    // up (pass up: "z" for the CAD convention). Its winding is made outward by the sign of
    // its volume.
    function mesh(text, up) {
      const solid = /^\s*solid\b/im.test(text) && /^\s*vertex\b/im.test(text);
      let triangles = solid ? meshStl(text) : meshObj(text);
      if (!triangles.length) throw new Error("mesh: no triangles found");
      if (up === "z") triangles = triangles.map((t) => t.map((p) => [p[0], p[2], -p[1]]));
      const flat = triangles.flat();
      const mid = [0, 1, 2].map((a) => { const [lo, hi] = minMax(flat.map((p) => p[a])); return (lo + hi) / 2.0; });
      const pos = [];
      flat.forEach((v) => { pos.push(v[0] - mid[0], v[1] - mid[1], v[2] - mid[2]); });
      const tris = flat.map((_, i) => i);
      const bright = flat.map(() => MESH_BRIGHTNESS);
      const made = new Mesh(pos, tris, bright);
      if (made.volume() >= 0) return made;
      const turned = [];
      for (let i = 0; i < tris.length; i += 3) turned.push(tris[i], tris[i + 2], tris[i + 1]);
      return new Mesh(pos, turned, bright);
    }

    // ---- Face::Head (the mesh) ----------------------------------------------
    const MESHCFG = ascii.mesh;
    const BLUR = MESHCFG.blur;
    // The painting's face ellipse (DepthMap's first layer, x radius 0.255 of the canvas) in the
    // same space as the eyes: its centre and half width, and where the skull and the jaw end.
    const CENTRE = ((CX * 2) - 1) * SPREAD;
    const MIDDLE = -((CY * 2) - 1) * SPREAD;
    const WIDEST = 0.255 * 2 * SPREAD;
    const TOP = MIDDLE + (WIDEST * MESHCFG.skull);
    const BOTTOM = MIDDLE - (WIDEST * MESHCFG.chin);
    const CENTRE_Y = (TOP + BOTTOM) / 2;
    const JAW = MESHCFG.jaw;
    const BACK = MESHCFG.back;
    const TIP_STEPS = 32;
    const CACHE_LIMIT = 8;

    const lumAt = (x, y) => lum(((x / SPREAD) + 1) / 2, (1 - (y / SPREAD)) / 2);

    // The painting's brightness blurred over a cross of radius BLUR: the relief.
    function height(x, y, centre) {
      return ((4 * (centre === undefined ? lumAt(x, y) : centre)) + (2 * (lumAt(x - BLUR, y) + lumAt(x + BLUR, y) + lumAt(x, y - BLUR) + lumAt(x, y + BLUR)))) / 12.0;
    }

    // Where the ridges and grooves lift or sink the surface, in the human head's own frame.
    function bumps(p, x, y, zone) {
      let lift = 0.0;
      if (p.beak_projection > 0) lift += beak(p, x, y);
      if (p.brow_ridge > 0) {
        const up = (y - p.brow_y) / p.brow_height;
        const across = x / p.brow_width;
        lift += p.brow_ridge * Math.exp(-(up * up)) * Math.exp(-(across * across * across * across));
      }
      if (p.socket_depth > 0 && zone >= 1 && zone <= 2) lift -= p.socket_depth * (zone === 1 ? 1.0 : 0.4);
      return lift;
    }

    // A ridge down the middle that grows toward its tip and ends there.
    function beak(p, x, y) {
      const t = (p.beak_top - y) / p.beak_length;
      if (t < 0) return 0.0;
      const past = (t - 1.0) * p.beak_length / 0.04;
      const taper = t <= 1.0 ? smoothstep(t) : Math.exp(-(past * past));
      const side = x / p.beak_width;
      return p.beak_projection * taper * Math.exp(-(side * side));
    }

    class Head {
      constructor(rows, cols) {
        this.rings = clamp(halfUp(rows * MESHCFG.per_row), MESHCFG.rows[0], MESHCFG.rows[1]);
        const around = clamp(halfUp(cols * MESHCFG.per_col), MESHCFG.around[0], MESHCFG.around[1]);
        this.around = around % 2 === 1 ? around + 1 : around;
        this.meshes = new Map();
        this.grid();
      }

      // The human head, or the named mask's, on the same grid.
      mesh(name) {
        const key = name === undefined || name === null ? "" : name;
        if (!this.meshes.has(key)) this.meshes.set(key, this.build(maskParams(name === undefined ? null : name), name === undefined ? null : name));
        return this.meshes.get(key);
      }

      get triangleCount() { return this.tris.length / 3; }

      // Half the head's width at height y: the skull an ellipse, the jaw the same ellipse under
      // mesh.jaw.
      halfAt(y) {
        const up = y > MIDDLE;
        const t = (y - MIDDLE) / (up ? TOP - MIDDLE : MIDDLE - BOTTOM);
        const shape = Math.max(1.0 - (t * t), 0.0);
        return WIDEST * (up ? Math.sqrt(shape) : Math.pow(shape, JAW));
      }

      // Where a point of the painting (x about the centre, y as painted) sits on the surface
      // under params p: x is clamped to the head's width at y.
      surface(p, xc, y) {
        const half = this.halfAt(y);
        const s = clamp(xc / half, -1.0, 1.0);
        const xa = xc + CENTRE;
        return this.vertex(p, half, y, s, Math.sqrt(1.0 - (s * s)), height(xa, y), zoneAt(xa, y));
      }

      grid() {
        const n = this.around;
        const rings = this.rings;
        this.ringY = []; this.ringHalf = [];
        for (let j = 0; j < rings; j += 1) {
          this.ringY.push(TOP - (((TOP - BOTTOM) * (j + 1)) / (rings + 1)));
          this.ringHalf.push(this.halfAt(this.ringY[j]));
        }
        this.sin = []; this.cos = [];
        for (let i = 0; i < n; i += 1) { this.sin.push(Math.sin(2 * Math.PI * i / n)); this.cos.push(Math.cos(2 * Math.PI * i / n)); }
        this.lum = []; this.paint = []; this.zone = [];
        this.ringY.forEach((y, j) => {
          for (let i = 0; i < n; i += 1) {
            const xa = (this.ringHalf[j] * this.sin[i]) + CENTRE;
            const front = this.cos[i] > 0;
            const painted = front ? lumAt(xa, y) : 0.5;
            this.paint.push(painted);
            this.lum.push(front ? height(xa, y, painted) : 0.5);
            this.zone.push(front ? zoneAt(xa, y) : SKIN_ZONE);
          }
        });
        this.tris = this.triangles();
      }

      // Outward winding, front at ring column 0, rings running down.
      triangles() {
        const n = this.around;
        const top = this.rings * n;
        const tris = [];
        for (let i = 0; i < n; i += 1) tris.push(top, i, (i + 1) % n);
        for (let j = 0; j < this.rings - 1; j += 1) {
          for (let i = 0; i < n; i += 1) {
            const a = (j * n) + i;
            const b = (j * n) + ((i + 1) % n);
            const c = ((j + 1) * n) + i;
            const d = ((j + 1) * n) + ((i + 1) % n);
            tris.push(a, c, b, b, c, d);
          }
        }
        const last = (this.rings - 1) * n;
        for (let i = 0; i < n; i += 1) tris.push(top + 1, last + ((i + 1) % n), last + i);
        return tris;
      }

      build(p, name) {
        const pos = [];
        const bright = [];
        let reach = 0.0;
        for (let j = 0; j < this.rings; j += 1) {
          for (let i = 0; i < this.around; i += 1) {
            const k = (j * this.around) + i;
            const v = this.vertex(p, this.ringHalf[j], this.ringY[j], this.sin[i], this.cos[i], this.lum[k], this.zone[k]);
            pos.push(v[0], v[1], v[2]);
            if (Math.abs(v[0]) > reach) reach = Math.abs(v[0]);
            bright.push(this.shade(p, this.paint[k], this.cos[i]));
          }
        }
        [TOP, BOTTOM].forEach((y) => {
          pos.push(0.0, (y - CENTRE_Y) * p.facial_verticalization * p.face_length, 0.0);
          bright.push(BACK);
        });
        const named = name !== null && name !== undefined;
        return new Mesh(pos, this.tris, bright, { landmarks: this.landmarks(p), params: named ? p : null, margins: named ? maskMargins(p, reach) : [0.0, 0.0] });
      }

      // A vertex under params p: the ring's half width, its height y as painted, the angle's
      // sine and cosine, the painting's relief there and its zone.
      vertex(p, half, y, sin, cos, relief, zone) {
        const baseY = (y - CENTRE_Y) * p.facial_verticalization;
        const upper = clamp((baseY + 0.38) / 0.80, 0.0, 1.0);
        const scale = p.lower_face_scale + ((p.upper_face_scale - p.lower_face_scale) * upper);
        const across = half * sin * scale;
        const depth = half * 1.10 * p.jaw_projection * p.jaw_softening * p.masticatory_scale * p.cranium_scale * p.depth_scale;
        const front = cos > 0 ? cos : 0.0;
        const lift = ((relief - 0.5) * 0.20 * p.nasal_projection * p.relief) + bumps(p, across, baseY, zone);
        return [across * p.cranial_width * p.width, baseY * p.face_length, (depth * cos) + (front * lift)];
      }

      // The vertex's painted brightness: the painting at the front, fading to the back's flat
      // tone round the side, pulled toward flat by a mask.
      shade(p, painted, cos) {
        const w = Math.min((cos > 0 ? cos : 0.0) * 2.0, 1.0);
        const b = BACK + ((painted - BACK) * w);
        return b + ((p.flat_brightness - b) * p.flatten);
      }

      // Where the face's parts stand on the surface under p, for the features.
      landmarks(p) {
        const eyeY = EYES[0][1];
        const reach = 0.8 * SOCKET[0];
        const eyes = EYES.map(([ex, ey]) => ({
          left: this.surface(p, ex - CENTRE - reach, ey),
          right: this.surface(p, ex - CENTRE + reach, ey),
          pupil: this.surface(p, ex - CENTRE, ey),
        }));
        const mouth = {
          left: this.surface(p, MOUTH[0] - CENTRE - MOUTH_REACH, MOUTH[1]),
          right: this.surface(p, MOUTH[0] - CENTRE + MOUTH_REACH, MOUTH[1]),
          centre: this.surface(p, MOUTH[0] - CENTRE, MOUTH[1]),
        };
        const low = MOUTH[1] + 0.05;
        let tip = null;
        for (let k = 0; k < TIP_STEPS; k += 1) {
          const point = this.surface(p, 0.0, eyeY + ((low - eyeY) * (k + 0.5) / TIP_STEPS));
          if (tip === null || point[2] > tip[2]) tip = point;
        }
        return { eyes, mouth, bridge: this.surface(p, 0.0, eyeY), tip };
      }
    }

    function head(rows, cols) { return new Head(rows, cols); }

    // How far past the head the extras reach, as [above, to the side].
    function maskMargins(p, reach) {
      const above = p.halo > 0 ? (p.halo_rise * p.halo) + ((halfUp(p.halo_rows) - 1) * p.halo_gap) : 0.0;
      return [above, p.disc > 0 ? reach + (p.disc_offset * p.disc) + (p.disc_radius * p.disc) : 0.0];
    }

    // The mesh for a mask at a mix: the head's at 0, the mask's at 1, and between them every
    // vertex blended by the same smoothstep as the numbers.
    function maskSource(headObj, name, amount) {
      if (name === null || name === undefined || !(amount > 0.0)) return headObj.mesh();
      const target = headObj.mesh(name);
      if (amount >= 1.0) return target;
      return Mesh.morph(headObj.mesh(), target, smoothstep(amount), morph(NEUTRAL, maskParams(name), amount));
    }

    // ---- Face::Ascii --------------------------------------------------------
    const CAMERA = ascii.camera;
    const FIT = ascii.fit;
    const SAMPLES = Math.trunc(ascii.samples);
    const LARGE = ascii.samples_large;
    // Samples a side: the full count, fewer on a window big enough that the cells carry the detail.
    function samplesFor(rows, cols) { return rows * cols >= LARGE.cells ? Math.trunc(LARGE.samples) : SAMPLES; }
    const COVER = ascii.cover;
    const EDGE_FADE = ascii.edge_fade;
    const EDGE = ascii.edge_gradient;
    const CREASE = ascii.crease;
    const PAINT = ascii.shade.paint;
    const GAIN = ascii.shade.gain;
    const GAMMA = ascii.shade.gamma;
    const DEPTH_EDGE = ascii.depth_edge;
    const VOTE = ascii.vote;
    const CEILING = ascii.shade.ceiling;
    const NEAR = ascii.depth.near;
    const FAR = ascii.depth.far;
    const DEPTH_TONE = ascii.depth.tone;
    const OCCLUSION = ascii.occlusion;
    const FACING = ascii.facing;
    const LIGHT = ascii.light;
    const ELEVATION = LIGHT.elevation;
    const AMBIENT = LIGHT.ambient;
    const KEY = LIGHT.key;
    const FILL = LIGHT.fill;
    const RIM = LIGHT.rim;
    const SPEC = LIGHT.spec;
    // Shininess is a power of two, taken by squaring this many times.
    let SQUARINGS = 0;
    for (let s = Math.trunc(LIGHT.shininess); s > 1; s = Math.floor(s / 2)) SQUARINGS += 1;
    const FEATURE = ascii.features;
    const MIN_ROWS = ascii.min_rows;
    const MIN_COLS = ascii.min_cols;
    const SHUT = 0.5;

    function unit(x, y, z) {
      const length = Math.sqrt((x * x) + (y * y) + (z * z));
      return [x / length, y / length, z / length];
    }

    const FILL_DIR = unit(LIGHT.fill_dir[0], LIGHT.fill_dir[1], LIGHT.fill_dir[2]);

    class Frame {
      constructor(chars, depth) {
        this.chars = chars;
        this.depth = depth;
      }

      // Trimmed, as the fixtures hold them.
      get lines() { return this.chars.map((row) => row.join("").replace(/ +$/, "")); }

      toString() { return this.chars.map((row) => row.join("")).join("\n"); }
    }

    class Renderer {
      // The source answers mesh(): a Head or a Mesh does.
      constructor(source, rows, cols, options) {
        const opts = options || {};
        this.m = source.mesh();
        this.rows = rows;
        this.cols = cols;
        this.samples = samplesFor(rows, cols);
        this.perCell = this.samples * 2 * this.samples;
        this.sw = cols * this.samples;
        this.sh = rows * 2 * this.samples;
        this.ramp = ramp(opts.chars, opts.mode);
        this.levels = levels(this.ramp, opts.mode);
        const [above, aside] = this.m.margins;
        const [xlo, xhi, ylo, yhi, reach] = this.m.bounds();
        this.lift = (ylo + yhi + above) / 2.0;
        this.scale = Math.min(((cols / 2.0) - 1) / Math.max(reach, aside), ((rows * 2) - 2) / (yhi - ylo + above)) * FIT;
        this.anchors = this.m.landmarks;
        this.mask = this.m.params;
        this.top = yhi;
        this.side = Math.max(-xlo, xhi);
      }

      // The vertices as fitted (x, y, z, brightness), which the fixtures fingerprint: the
      // digest is a sha256 of them formatted by Ruby, whose %.4f rounds near-ties its own way.
      fitted() {
        const out = [];
        for (let v = 0; v < this.m.vertexCount; v += 1) out.push([this.m.pos[3 * v], this.m.pos[(3 * v) + 1] - this.lift, this.m.pos[(3 * v) + 2], this.m.bright[v]]);
        return out;
      }

      render(look, state) {
        this.turn(look);
        this.transform();
        this.raster();
        this.light();
        this.measure();
        this.frame = new Frame(
          Array.from({ length: this.rows }, () => new Array(this.cols).fill(" ")),
          Array.from({ length: this.rows }, () => new Array(this.cols).fill(1)),
        );
        for (let r = 0; r < this.rows; r += 1) for (let c = 0; c < this.cols; c += 1) this.cell(c, r);
        if (this.anchors) this.drawFeatures(look, state || "idle");
        return this.frame;
      }

      // A source-space point in sub-pixels (a cell is one wide and two tall), and its depth.
      project(x, y, z) {
        const [rx, ry, rz] = this.rotate(x, y - this.lift, z);
        const k = this.gain * this.camera / (this.camera - rz);
        return [(this.cols / 2.0) + (rx * k), this.rows - (ry * k) - this.bob, rz * this.scale];
      }

      covered(px, py) {
        const x = Math.floor(px * this.samples);
        const y = Math.floor(py * this.samples);
        return x >= 0 && x <= this.sw - 1 && y >= 0 && y <= this.sh - 1 && this.tri[(y * this.sw) + x] >= 0;
      }

      // Whether a landmark's side of the head, from the axis out through it, is turned toward
      // the viewer: a feature at the limb is not seen.
      facing(x, z) {
        const reach = Math.sqrt((x * x) + (z * z));
        return reach === 0 || this.rotate(x, 0.0, z)[2] / reach >= FACING;
      }

      hidden(px, py, depth, slack) {
        const x = Math.floor(px * this.samples);
        const y = Math.floor(py * this.samples);
        if (!(x >= 0 && x <= this.sw - 1 && y >= 0 && y <= this.sh - 1)) return true;
        return this.zb[(y * this.sw) + x] > depth + OCCLUSION + (slack || 0.0);
      }

      turn(look) {
        const angles = [look.yaw + look.turn, look.pitch, look.roll];
        this.cy = Math.cos(angles[0]); this.sy = Math.sin(angles[0]);
        this.cp = Math.cos(angles[1]); this.sp = Math.sin(angles[1]);
        this.cr = Math.cos(angles[2]); this.sr = Math.sin(angles[2]);
        this.camera = CAMERA / look.dolly;
        this.gain = this.scale * look.scale;
        this.bob = look.bob * this.scale;
        this.key = unit(Math.sin(look.light) * Math.cos(ELEVATION), Math.sin(ELEVATION), Math.cos(look.light) * Math.cos(ELEVATION));
        this.rim = unit(-Math.sin(look.light), 0.4, -Math.cos(look.light));
        this.halfway = unit(this.key[0], this.key[1], this.key[2] + 1.0);
      }

      // Yaw, then pitch, then roll: x right, y up, z toward the viewer.
      rotate(x, y, z) {
        const a = (x * this.cy) + (z * this.sy);
        const b = (-x * this.sy) + (z * this.cy);
        const y2 = (y * this.cp) - (b * this.sp);
        return [(a * this.cr) - (y2 * this.sr), (a * this.sr) + (y2 * this.cr), (y * this.sp) + (b * this.cp)];
      }

      // Every vertex and normal turned, and the vertices in the sample grid.
      transform() {
        const pos = this.m.pos;
        const norm = this.m.normals();
        const n = this.m.vertexCount;
        this.sx = new Array(n); this.sy_ = new Array(n); this.sd = new Array(n);
        this.nx = new Array(n); this.ny = new Array(n); this.nz = new Array(n);
        for (let v = 0; v < n; v += 1) {
          const [x, y, z] = this.rotate(pos[3 * v], pos[(3 * v) + 1] - this.lift, pos[(3 * v) + 2]);
          const k = this.gain * this.camera / (this.camera - z);
          this.sx[v] = this.samples * ((this.cols / 2.0) + (x * k));
          this.sy_[v] = this.samples * (this.rows - (y * k) - this.bob);
          this.sd[v] = z * this.scale;
          const r = this.rotate(norm[3 * v], norm[(3 * v) + 1], norm[(3 * v) + 2]);
          this.nx[v] = r[0]; this.ny[v] = r[1]; this.nz[v] = r[2];
        }
      }

      // Edge functions at sample centres, largest depth wins and the first triangle keeps a
      // tie. A sample keeps its triangle and two weights.
      raster() {
        const total = this.sw * this.sh;
        this.zb = new Float64Array(total).fill(NONE);
        this.tri = new Int32Array(total).fill(-1);
        this.bu = new Float64Array(total);
        this.bv = new Float64Array(total);
        const tris = this.m.tris;
        const sx = this.sx; const sy = this.sy_; const sd = this.sd; const zb = this.zb; const sw = this.sw;
        const count = this.m.triangleCount;
        for (let t = 0; t < count; t += 1) {
          const i0 = tris[3 * t]; const i1 = tris[(3 * t) + 1]; const i2 = tris[(3 * t) + 2];
          const x0 = sx[i0]; const y0 = sy[i0]; const x1 = sx[i1]; const y1 = sy[i1]; const x2 = sx[i2]; const y2 = sy[i2];
          const area = ((x1 - x0) * (y2 - y0)) - ((x2 - x0) * (y1 - y0));
          if (!(area < -1.0e-9)) continue;
          const inv = 1.0 / area;
          const ix0 = Math.max(Math.ceil(Math.min(x0, x1, x2) - 0.5), 0);
          const ix1 = Math.min(Math.floor(Math.max(x0, x1, x2) - 0.5), sw - 1);
          const iy0 = Math.max(Math.ceil(Math.min(y0, y1, y2) - 0.5), 0);
          const iy1 = Math.min(Math.floor(Math.max(y0, y1, y2) - 0.5), this.sh - 1);
          if (!(ix0 <= ix1 && iy0 <= iy1)) continue;
          const z0 = sd[i0]; const z1 = sd[i1]; const z2 = sd[i2];
          const step0 = y1 - y2; const step1 = y2 - y0; const step2 = y0 - y1;
          for (let j = iy0; j <= iy1; j += 1) {
            const py = j + 0.5;
            const px = ix0 + 0.5;
            let e0 = ((x2 - x1) * (py - y1)) - ((y2 - y1) * (px - x1));
            let e1 = ((x0 - x2) * (py - y2)) - ((y0 - y2) * (px - x2));
            let e2 = ((x1 - x0) * (py - y0)) - ((y1 - y0) * (px - x0));
            let idx = (j * sw) + ix0;
            for (let i = ix0; i <= ix1; i += 1) {
              const b0 = e0 * inv; const b1 = e1 * inv; const b2 = e2 * inv;
              if (b0 >= 0.0 && b1 >= 0.0 && b2 >= 0.0) {
                const z = (b0 * z0) + (b1 * z1) + (b2 * z2);
                if (z > zb[idx]) { zb[idx] = z; this.tri[idx] = t; this.bu[idx] = b1; this.bv[idx] = b2; }
              }
              e0 += step0; e1 += step1; e2 += step2; idx += 1;
            }
          }
        }
      }

      // Light every covered sample and keep its luminance and the slope of its surface.
      light() {
        const total = this.sw * this.sh;
        this.lum = new Float64Array(total);
        this.slopeX = new Float64Array(total);
        this.slopeY = new Float64Array(total);
        const tris = this.m.tris; const bright = this.m.bright; const cavity = this.m.cavity();
        for (let idx = 0; idx < total; idx += 1) {
          const t = this.tri[idx];
          if (t < 0) continue;
          const b1 = this.bu[idx]; const b2 = this.bv[idx]; const b0 = 1.0 - b1 - b2;
          const i0 = tris[3 * t]; const i1 = tris[(3 * t) + 1]; const i2 = tris[(3 * t) + 2];
          const n = unit((b0 * this.nx[i0]) + (b1 * this.nx[i1]) + (b2 * this.nx[i2]), (b0 * this.ny[i0]) + (b1 * this.ny[i1]) + (b2 * this.ny[i2]),
            (b0 * this.nz[i0]) + (b1 * this.nz[i1]) + (b2 * this.nz[i2]));
          this.lum[idx] = this.radiance(n[0], n[1], n[2], (b0 * bright[i0]) + (b1 * bright[i1]) + (b2 * bright[i2]), (b0 * cavity[i0]) + (b1 * cavity[i1]) + (b2 * cavity[i2]));
          const flat = n[2] > 0.25 ? n[2] : 0.25;
          this.slopeX[idx] = -n[0] / flat;
          this.slopeY[idx] = n[1] / flat;
        }
      }

      radiance(nx, ny, nz, brightness, ao) {
        const k = (nx * this.key[0]) + (ny * this.key[1]) + (nz * this.key[2]);
        const f = (nx * FILL_DIR[0]) + (ny * FILL_DIR[1]) + (nz * FILL_DIR[2]);
        const r = (nx * this.rim[0]) + (ny * this.rim[1]) + (nz * this.rim[2]);
        let lumen = (AMBIENT + (KEY * (k > 0.0 ? k : 0.0)) + (FILL * (f > 0.0 ? f : 0.0)) + (RIM * (r > 0.0 ? r : 0.0))) * (1.0 - PAINT + (PAINT * brightness));
        if (k > 0.0) {
          let h = (nx * this.halfway[0]) + (ny * this.halfway[1]) + (nz * this.halfway[2]);
          if (h > 0.0) {
            for (let s = 0; s < SQUARINGS; s += 1) h *= h;
            lumen += SPEC * h;
          }
        }
        return lumen * (1.0 - ao);
      }

      // Per cell: covered samples, their luminance and depth summed; and the depth range.
      measure() {
        const cells = this.rows * this.cols;
        this.count = new Array(cells).fill(0);
        this.lumSum = new Array(cells).fill(0.0);
        this.depthSum = new Array(cells).fill(0.0);
        let lo = Infinity; let hi = -Infinity;
        for (let r = 0; r < this.rows; r += 1) {
          for (let c = 0; c < this.cols; c += 1) {
            const cell = (r * this.cols) + c;
            for (let dy = 0; dy < 2 * this.samples; dy += 1) {
              const base = (((r * 2 * this.samples) + dy) * this.sw) + (c * this.samples);
              for (let dx = 0; dx < this.samples; dx += 1) {
                if (this.tri[base + dx] < 0) continue;
                const d = this.zb[base + dx];
                this.count[cell] += 1;
                this.lumSum[cell] += this.lum[base + dx];
                this.depthSum[cell] += d;
                if (d < lo) lo = d;
                if (d > hi) hi = d;
              }
            }
          }
        }
        this.nearLo = lo === Infinity ? 0.0 : lo;
        this.nearSpan = Math.max((hi === -Infinity ? 0.0 : hi) - this.nearLo, 1.0);
      }

      coverage(c, r) {
        return c >= 0 && c < this.cols && r >= 0 && r < this.rows ? this.count[(r * this.cols) + c] / this.perCell : 0.0;
      }

      cell(c, r) {
        const i = (r * this.cols) + c;
        const cover = this.count[i] / this.perCell;
        if (cover < COVER) return;
        const edge = (c > 0 && this.coverage(c - 1, r) < COVER) || (c < this.cols - 1 && this.coverage(c + 1, r) < COVER)
          || (r > 0 && this.coverage(c, r - 1) < COVER) || (r < this.rows - 1 && this.coverage(c, r + 1) < COVER);
        const fraction = this.depthAt(i);
        const glyph = edge ? this.silhouette(c, r) : (this.step(c, r, fraction) || this.crease(c, r));
        this.frame.chars[r][c] = glyph || this.shade(c, r, i, cover, fraction);
        this.frame.depth[r][c] = fraction >= NEAR ? 2 : (fraction <= FAR ? 0 : 1);
      }

      // The glyph for the cell's boundary, from the gradient of coverage over the 3x3 cells.
      silhouette(c, r) {
        let gx = 0.0; let gy = 0.0;
        [-1, 0, 1].forEach((d) => {
          const weight = d === 0 ? 2.0 : 1.0;
          gx += weight * (this.coverage(c + 1, r + d) - this.coverage(c - 1, r + d));
          gy += weight * (this.coverage(c + d, r + 1) - this.coverage(c + d, r - 1));
        });
        gy /= 2.0;
        if (hypot(gx, gy) < EDGE) return null;
        const glyph = line(gy, gx);
        if (glyph !== "-") return glyph;
        const covered = [0, 0];
        for (let dy = 0; dy < 2 * this.samples; dy += 1) {
          const base = (((r * 2 * this.samples) + dy) * this.sw) + (c * this.samples);
          for (let dx = 0; dx < this.samples; dx += 1) if (this.tri[base + dx] >= 0) covered[Math.floor(dy / this.samples)] += 1;
        }
        return level(covered[0] >= this.samples * this.samples / 2.0, covered[1] >= this.samples * this.samples / 2.0, gy < 0);
      }

      // A cell's mean depth as a fraction of the visible range.
      depthAt(i) { return ((this.depthSum[i] / this.count[i]) - this.nearLo) / this.nearSpan; }

      // An occluding step inside the surface: the depth jumps by more than depth_edge to a
      // neighbouring cell; the line runs across the depth gradient.
      step(c, r, fraction) {
        let jump = 0.0;
        const here = (r * this.cols) + c;
        if (c > 0 && this.count[here - 1] > 0) jump = Math.max(jump, Math.abs(this.depthAt(here - 1) - fraction));
        if (c < this.cols - 1 && this.count[here + 1] > 0) jump = Math.max(jump, Math.abs(this.depthAt(here + 1) - fraction));
        if (r > 0 && this.count[here - this.cols] > 0) jump = Math.max(jump, Math.abs(this.depthAt(here - this.cols) - fraction));
        if (r < this.rows - 1 && this.count[here + this.cols] > 0) jump = Math.max(jump, Math.abs(this.depthAt(here + this.cols) - fraction));
        if (jump < DEPTH_EDGE) return null;
        const gx = this.depthGradient(c - 1, r, c + 1, r, fraction);
        const gy = this.depthGradient(c, r - 1, c, r + 1, fraction) / 2.0;
        if (gx === 0 && gy === 0) return null;
        return line(gy, gx);
      }

      depthGradient(c0, r0, c1, r1, fraction) {
        const has = (c, r) => c >= 0 && c < this.cols && r >= 0 && r < this.rows && this.count[(r * this.cols) + c] > 0;
        const lo = has(c0, r0) ? this.depthAt((r0 * this.cols) + c0) : fraction;
        const hi = has(c1, r1) ? this.depthAt((r1 * this.cols) + c1) : fraction;
        return hi - lo;
      }

      // Where the surface's slope changes: each covered sample with four covered neighbours
      // reads the change of slope across itself and, if the larger |eigenvalue| (scaled to a
      // cell's width) reaches crease, votes for the glyph of the ridge's direction. The cell
      // takes the glyph with most votes when they are at least vote of its covered samples.
      crease(c, r) {
        let horizontal = 0; let diagonalUp = 0; let vertical = 0; let diagonalDown = 0;
        let seen = 0;
        for (let dy = 0; dy < 2 * this.samples; dy += 1) {
          const y = (r * 2 * this.samples) + dy;
          if (y === 0 || y >= this.sh - 1) continue;
          for (let dx = 0; dx < this.samples; dx += 1) {
            const x = (c * this.samples) + dx;
            const idx = (y * this.sw) + x;
            if (this.tri[idx] < 0) continue;
            seen += 1;
            if (x === 0 || x >= this.sw - 1) continue;
            const l = idx - 1; const rt = idx + 1; const u = idx - this.sw; const d = idx + this.sw;
            if (this.tri[l] < 0 || this.tri[rt] < 0 || this.tri[u] < 0 || this.tri[d] < 0) continue;
            const xx = (this.slopeX[rt] - this.slopeX[l]) / 2.0;
            const yy = (this.slopeY[d] - this.slopeY[u]) / 2.0;
            const xy = ((this.slopeY[rt] - this.slopeY[l]) + (this.slopeX[d] - this.slopeX[u])) / 4.0;
            const spread = (xx - yy) / 2;
            const hf = Math.sqrt((spread * spread) + (xy * xy));
            const mid = (xx + yy) / 2;
            const major = mid + hf;
            const minor = mid - hf;
            if (this.samples * Math.max(Math.abs(major), Math.abs(minor)) < CREASE) continue;
            const angle = 0.5 * Math.atan2(2 * xy, xx - yy);
            const g = Math.abs(major) >= Math.abs(minor) ? line(-Math.sin(angle), -Math.cos(angle)) : line(-Math.cos(angle), Math.sin(angle));
            if (g === "-") horizontal += 1;
            else if (g === "/") diagonalUp += 1;
            else if (g === "|") vertical += 1;
            else diagonalDown += 1;
          }
        }
        if (seen === 0) return null;
        // Ties go to the glyph later in character order.
        let votes = horizontal; let glyph = "-";
        if (diagonalUp >= votes) { votes = diagonalUp; glyph = "/"; }
        if (diagonalDown >= votes) { votes = diagonalDown; glyph = "\\"; }
        if (vertical >= votes) { votes = vertical; glyph = "|"; }
        return votes >= VOTE * seen && votes > 0 ? glyph : null;
      }

      shade(c, r, i, cover, fraction) {
        let tone = GAIN * (this.lumSum[i] / this.count[i]) * (1.0 - EDGE_FADE + (EDGE_FADE * cover));
        tone = Math.pow(clamp(tone, 0.0, CEILING), GAMMA) + (DEPTH_TONE * (fraction - 0.5));
        return this.ramp[index(clamp(tone, 0.0, 1.0), this.levels, c, r)];
      }

      // ---- Face::Features ---------------------------------------------------
      cellOf(point, slack) {
        const [px, py, depth] = this.project(point[0], point[1], point[2]);
        return [px, py, depth, this.hidden(px, py, depth, slack) || !this.covered(px, py) || !this.facing(point[0], point[2])];
      }

      put(col, row, glyph) {
        if (!(row >= 0 && row < this.frame.chars.length && col >= 0 && col < this.frame.chars[0].length)) return;
        this.frame.chars[row][col] = glyph;
        this.frame.depth[row][col] = 2;
      }

      run(col, row, glyphs) {
        Array.from(glyphs).forEach((g, i) => this.put(col + i, row, g));
      }

      drawFeatures(look, state) {
        this.look = look;
        const mask = this.mask;
        this.rings = !!(mask?.ring >= MASK_TAKEOVER);
        this.slack = mask ? (mask.beak_projection + mask.brow_ridge) * this.scale : 0.0;
        this.mouthSlack = mask ? MOUTH_SLACK * this.scale : 0.0;
        this.anchors.eyes.forEach((eye) => (this.rings ? this.ringEye(eye) : this.eyebrowAndEye(eye)));
        this.nose();
        this.mouth(state);
        if (!mask) return;
        this.halo();
        this.discs();
      }

      eyebrowAndEye(eye) {
        const [lx, , , lh] = this.cellOf(eye.left);
        const [rx, , , rh] = this.cellOf(eye.right);
        if (lh && rh) return;
        const [px, py, , ph] = this.cellOf(eye.pupil);
        if (ph) return;
        const span = Math.floor(Math.abs(rx - lx));
        const width = Math.min(span % 2 === 0 ? span + 1 : span, Math.max(FEATURE.eye_floor, Math.floor(this.frame.chars[0].length * FEATURE.eye_share)));
        const col = halfUp(px);
        const row = Math.floor(py / 2);
        if (width < 3) {
          this.put(col, row, this.look.eye_open < SHUT ? FEATURE.lid : FEATURE.pupil);
          return;
        }
        const left = col - half(width);
        const tall = width >= FEATURE.eye_tall_at;
        const lift = tall ? 2 : 0;
        if (this.look.eye_open < SHUT) {
          this.run(left, row, FEATURE.lid.repeat(width));
        } else {
          const inner = width - 2;
          const reach = half(inner);
          const glance = clamp(halfUp(this.look.gaze[0] * 14), -reach, reach);
          this.run(left, row, FEATURE.eye_open + " ".repeat(inner) + FEATURE.eye_close);
          if (tall) this.almond(left, row, width);
          this.put(col + glance, row, tall ? FEATURE.pupil_large : FEATURE.pupil);
        }
        if (!this.mask || this.mask.brow_line >= 0.5) this.run(left, row - 1 - lift, FEATURE.brow.repeat(width));
        if (this.mask && this.mask.brow_ridge >= BROW_MIN) this.run(left, row - 2 - lift, MASK_GLYPHS.brow_heavy.repeat(width));
      }

      // An eye wide enough to have lids: one a row above the line of the eye, one below.
      almond(left, row, width) {
        const top = FEATURE.eye_lid_top;
        const bottom = FEATURE.eye_lid_bottom;
        this.run(left, row - 1, top[0] + top[1].repeat(width - 2) + top[2]);
        this.run(left, row + 1, bottom[0] + bottom[1].repeat(width - 2) + bottom[2]);
      }

      nose() {
        if (this.mask && this.mask.nose_line < 0.5) return;
        const [bx, by, , bh] = this.cellOf(this.anchors.bridge);
        const [tx, ty, , th] = this.cellOf(this.anchors.tip);
        if (bh || th) return;
        if (this.mask && this.mask.beak_projection >= BEAK_MIN) { this.beak(bx, by, tx, ty); return; }
        const steps = Math.ceil(Math.max(Math.abs(tx - bx), Math.abs(ty - by) / 2));
        const glyph = line(tx - bx, by - ty);
        for (let i = 0; i < steps; i += 1) {
          const f = i / steps;
          this.put(halfUp(bx + ((tx - bx) * f)), Math.floor((by + ((ty - by) * f)) / 2), glyph);
        }
        this.put(halfUp(tx), Math.floor(ty / 2), FEATURE.nose_tip);
        this.nostrils(tx, ty, Math.abs(ty - by) / 2);
      }

      // A nose long enough to show its nostrils: a pair flanking the tip.
      nostrils(tx, ty, length) {
        if (length < FEATURE.nostril_at) return;
        const wing = Math.min(Math.floor(length / FEATURE.nostril_at) + 1, 3);
        this.put(halfUp(tx) - wing, Math.floor(ty / 2), FEATURE.nostril[0]);
        this.put(halfUp(tx) + wing, Math.floor(ty / 2), FEATURE.nostril[1]);
      }

      // The nose as a ridge: two rails that part from the bridge toward the tip.
      beak(bx, by, tx, ty) {
        const tip = this.anchors.tip;
        const flare = Math.abs(this.project(tip[0] + this.mask.beak_flare, tip[1], tip[2])[0] - tx);
        const steps = Math.ceil(Math.max(Math.abs(tx - bx), Math.abs(ty - by) / 2));
        const rails = [-1, 1].map((side) => [side, line((tx + (side * flare)) - bx, by - ty)]);
        for (let i = 0; i < steps; i += 1) {
          const f = i / steps;
          const y = Math.floor((by + ((ty - by) * f)) / 2);
          rails.forEach(([side, glyph]) => this.put(halfUp(bx + ((tx - bx) * f) + (side * flare * f)), y, glyph));
        }
        const tipGlyph = MASK_GLYPHS.beak_tip;
        this.run(halfUp(tx) - half(tipGlyph.length), Math.floor(ty / 2), tipGlyph);
      }

      // Eyes as concentric rings of the eye's own plane, outermost glyph first.
      ringEye(eye) {
        const [px, py, , ph] = this.cellOf(eye.pupil);
        if (ph || (this.cellOf(eye.left)[3] && this.cellOf(eye.right)[3])) return;
        const count = halfUp(this.mask.ring_count);
        const radius = this.mask.ring_radius * this.mask.ring;
        this.clear(eye.pupil, radius);
        const glyphs = MASK_GLYPHS.ring;
        for (let i = 1; i <= count; i += 1) this.circle(eye.pupil, radius * i / count, glyphs[(count - i) % glyphs.length]);
        this.put(halfUp(px), Math.floor(py / 2), this.look.eye_open < SHUT ? FEATURE.lid : FEATURE.pupil);
      }

      // An arc above the crown in the contour glyphs, a row of it per arc.
      halo() {
        const m = this.mask;
        const span = m.halo_span * m.halo;
        if (span < 1.0) return;
        const radius = m.halo_radius;
        const centre = this.top + (m.halo_rise * m.halo) - radius;
        const steps = Math.ceil(2 * span);
        const rows = halfUp(m.halo_rows);
        for (let row = 0; row < rows; row += 1) {
          const r = radius - (row * m.halo_gap);
          const seen = [];
          for (let i = 0; i <= steps; i += 1) {
            const angle = (-span + (2 * span * i / steps)) * Math.PI / 180;
            seen.push(this.project(r * Math.sin(angle), centre + (r * Math.cos(angle)), 0.0));
          }
          seen.forEach(([px, py, depth], i) => {
            if (this.hidden(px, py, depth)) return;
            const before = seen[Math.max(i - 1, 0)];
            const after = seen[Math.min(i + 1, steps)];
            let glyph = line(after[0] - before[0], before[1] - after[1]);
            if (glyph === "-") glyph = MASK_GLYPHS.halo[row > 0 ? 1 : 0];
            this.put(halfUp(px), Math.floor(py / 2), glyph);
          });
        }
      }

      // A pair of ear discs, each two circles, at the head's widest.
      discs() {
        const m = this.mask;
        const radius = m.disc_radius * m.disc;
        if (radius <= 0.0) return;
        const y = (kbSum(this.anchors.eyes.map((e) => e.pupil[1])) / 2.0) + m.disc_height;
        [-1, 1].forEach((side) => {
          const centre = [side * (this.side + (m.disc_offset * m.disc)), y, 0.0];
          Array.from(MASK_GLYPHS.disc).forEach((g, i) => this.circle(centre, radius * (1.0 - (i * 0.5)), g));
        });
      }

      // Blank every cell whose centre falls within r of a point, so rings stand on clear ground.
      clear(centre, r) {
        const [cx, cy] = this.project(centre[0], centre[1], centre[2]);
        const edge = Math.abs(this.project(centre[0] + r, centre[1], centre[2])[0] - cx);
        if (edge < RING_MIN_PX) return;
        const mid = Math.floor(cy / 2);
        for (let row = mid - Math.ceil(edge); row <= mid + Math.ceil(edge); row += 1) {
          if (row < 0 || row >= this.frame.chars.length) continue;
          for (let col = Math.floor(cx - edge); col <= Math.ceil(cx + edge); col += 1) {
            if (col < 0 || col >= this.frame.chars[0].length) continue;
            if (hypot(col - cx, ((2 * row) + 1) - cy) <= edge) this.frame.chars[row][col] = " ";
          }
        }
      }

      // A circle of radius r in the head's x-y plane about a point.
      circle(centre, r, glyph) {
        const edge = this.project(centre[0] + r, centre[1], centre[2])[0] - this.project(centre[0], centre[1], centre[2])[0];
        if (Math.abs(edge) < RING_MIN_PX) return;
        const steps = Math.max(Math.ceil(9.42 * Math.abs(edge)), 12);
        for (let i = 0; i < steps; i += 1) {
          const angle = 2 * Math.PI * i / steps;
          const [px, py, depth] = this.project(centre[0] + (r * Math.cos(angle)), centre[1] + (r * Math.sin(angle)), centre[2]);
          if (!this.hidden(px, py, depth, this.slack)) this.put(halfUp(px), Math.floor(py / 2), glyph);
        }
      }

      mouth(state) {
        const spec = this.anchors.mouth;
        const [lx, , , lh] = this.cellOf(spec.left, this.mouthSlack);
        const [rx, , , rh] = this.cellOf(spec.right, this.mouthSlack);
        if (lh && rh) return;
        const mid = this.cellOf(spec.centre);
        const row = Math.floor(mid[1] / 2);
        const opened = this.look.mouth * this.look.mouth_open;
        let width = Math.max(halfUp(Math.abs(rx - lx) + 1), 2);
        width += halfUp(this.look.mouth_wide * width * 0.3);
        const left = halfUp(mid[0]) - half(width);
        if (Math.abs(lx - rx) < 1.5) { this.put(halfUp(mid[0]), row, FEATURE.nose); return; }
        if (opened > 0.12) {
          const drop = opened > 0.5 ? 2 : 1;
          const top = row - half(drop);
          const inner = Math.max(width - 2, 1);
          this.run(left, top, FEATURE.mouth_corner_top + FEATURE.mouth_line.repeat(inner) + FEATURE.mouth_corner_top);
          for (let i = 1; i < drop; i += 1) this.run(left, top + i, " ".repeat(inner + 2));
          this.run(left, top + drop, FEATURE.mouth_corner_bottom + FEATURE.mouth_line.repeat(inner) + FEATURE.mouth_corner_bottom);
        } else if (state === "listening") {
          const g = FEATURE.mouth_listening;
          this.run(left, row, g[0] + g[1].repeat(Math.max(width - 2, 1)) + g[2]);
        } else {
          this.run(left - 1, row - 1, " ".repeat(width + 2));
          this.run(left - 1, row + 1, " ".repeat(width + 2));
          this.run(left, row, FEATURE.mouth_line.repeat(width));
        }
      }
    }

    // ---- Face::Pose ---------------------------------------------------------
    const MOTION = ascii.motion;
    const STATES = ["idle", "listening", "thinking", "working", "speaking", "warning", "error", "sleeping", "ready"];
    const STILL_MODES = Array.isArray(contract?.state?.still_modes) ? contract.state.still_modes : ["idle"];

    // The mouth on a timer, for a player that gives no envelope back.
    function timedLevel(tick) {
      return clamp((Math.abs(Math.sin(tick * 1.1)) * 0.7) + (mod(tick, 3) * 0.15), 0.0, 1.0);
    }

    // The Look for a still frame as a pure function of (state, t, seed). since, from and
    // session (in extra) add the mask: without since there is none.
    function pose(state, t, seed, extra) {
      const sd = seed === undefined ? 0 : seed;
      const ex = extra || {};
      const masked = ex.since !== undefined && ex.since !== null;
      const spinning = MOTION.spin_states.indexOf(state) >= 0;
      const shut = mod(t + (mod(sd, 7) * 0.37), MOTION.blink_period) >= MOTION.blink_period - MOTION.blink_length;
      const k = Math.floor(t * FPS);
      return {
        yaw: 0.0,
        turn: spinning ? MOTION.spin * t : 0.0,
        pitch: MOTION.pitch_sway * Math.sin(MOTION.pitch_rate * t),
        roll: MOTION.roll * Math.sin(MOTION.roll_rate * t),
        scale: 1.0 + (MOTION.breath * Math.sin(MOTION.breath_rate * t)),
        dolly: num(MOTION.dolly[state], 1.0),
        bob: MOTION.bob * Math.sin(MOTION.bob_rate * t),
        light: LIGHT.start + (LIGHT.orbit * t),
        eye_open: shut ? 0.0 : 1.0,
        gaze: [0.0, 0.0],
        mouth: state === "speaking" ? timedLevel(k) : 0.0,
        mouth_open: 1.0,
        mouth_wide: 0.0,
        mask: masked ? pickMask(ex.session) : null,
        mix: masked ? maskMix(state, t, ex.since, ex.from) : 0.0,
      };
    }

    // What the page knows about the face this instant, mapped onto a Look the way the
    // terminal maps it: the state picks the Pose; while speaking the audio's level opens
    // the mouth (the timed level stands in when no envelope reached us) and the viseme
    // shapes it; reduced motion holds the head still and leaves the mouth and eyes alone.
    function lookFor(input) {
      const state = STATES.indexOf(input.state) >= 0 ? input.state : "idle";
      const look = pose(state, input.t, input.seed === undefined ? 1 : input.seed, { session: input.session, since: input.since, from: input.from });
      if (state === "speaking") {
        if (typeof input.level === "number" && Number.isFinite(input.level)) look.mouth = clamp(input.level, 0.0, 1.0);
        const shape = input.viseme && input.viseme !== "neutral" && input.shapes ? input.shapes[input.viseme] : null;
        if (shape) {
          look.mouth_open = clamp(num(shape.open, 1.0), 0.0, 1.0);
          look.mouth_wide = clamp(num(shape.wide, 0.0), -1.0, 1.0);
        }
      }
      if (STILL_MODES.includes(state)) {
        look.turn = 0.0;
        look.pitch = 0.0;
        look.roll = 0.0;
        look.scale = 1.0;
        look.dolly = 1.0;
        look.bob = 0.0;
        look.light = LIGHT.start;
        look.eye_open = 1.0;
        look.gaze = [0.0, 0.0];
      }
      if (input.reduced) {
        look.turn = 0.0; look.pitch = 0.0; look.roll = 0.0; look.scale = 1.0;
        look.dolly = 1.0; look.bob = 0.0; look.mix = 0.0; look.light = LIGHT.start;
      }
      return look;
    }

    // The state's name, centred, on an otherwise empty window (rows x cols cells).
    function word(text, rows, cols) {
      const lines = Array.from({ length: rows }, () => " ".repeat(cols));
      const clipped = String(text).slice(0, cols);
      const pad = Math.floor((cols - clipped.length) / 2);
      lines[Math.floor(rows / 2)] = (" ".repeat(pad) + clipped).padEnd(cols, " ");
      return lines;
    }

    // A frame's text and depth for a window: the head, or the state's name when the
    // window is too small for a face worth the name.
    const cache = new Map();
    const heads = new Map();
    function frame(options) {
      const rows = options.rows;
      const cols = options.cols;
      if (rows < MIN_ROWS || cols < MIN_COLS) return { word: true, lines: word(options.state, rows, cols), depth: null };
      const headKey = `${rows}x${cols}`;
      const key = `${headKey}|${String(options.mode || "")}|${String(options.chars || "")}`;
      let renderer = cache.get(key);
      if (!renderer) {
        if (cache.size >= 6) { cache.clear(); heads.clear(); }
        let built = heads.get(headKey);
        if (!built) {
          built = head(rows, cols);
          heads.set(headKey, built);
        }
        renderer = new Renderer(built, rows, cols, { chars: options.chars, mode: options.mode });
        cache.set(key, renderer);
      }
      // A morphed head is new every frame, so it is not kept.
      if (options.look.mix > 0) {
        renderer = new Renderer(maskSource(heads.get(headKey), options.look.mask, options.look.mix), rows, cols, { chars: options.chars, mode: options.mode });
      }
      const out = renderer.render(options.look, options.state);
      return { word: false, lines: out.chars.map((row) => row.join("")), depth: out.depth };
    }

    return {
      FPS, STATES, MIN_ROWS, MIN_COLS, ASPECT, DEFAULT_CHARS, MOTION,
      Glyphs: { line, level, ramp, levels, index, halfUp },
      DepthMap: { lum },
      head,
      mesh,
      Mesh,
      Renderer,
      pose,
      Masks: { ORDER: MASK_ORDER, params: maskParams, morph, mix: maskMix, pick: pickMask, source: maskSource, smoothstep },
      lookFor,
      timedLevel,
      frame,
      word,
    };
  }

  // ---- The page: a canvas of characters ------------------------------------
  // A monospace font at a cell twice as tall as it is wide, the head drawn by tone
  // (near bold, far dim) in the face's own colour, one fillText per row per tone.
  // The constitution's ranked law glyphs are applied after the head is rendered.
  // Occupied facial cells win; a glyph never overwrites an eye, contour, or mouth.
  const lawFieldConfig = root.MASTER_FACE_LAW_FIELD || {};
  let lawFieldVisible = lawFieldConfig.enabled !== false;
  function paintLawField(lines, depth, laws) {
    const cells = lines.map((line) => (Array.isArray(line) ? line.slice() : Array.from(String(line))));
    const tones = (depth || cells.map((row) => row.map(() => 1))).map((row) => row.slice());
    if (!cells.length || !cells[0].length || !Array.isArray(laws) || laws.length === 0) {
      return { lines: cells.map((row) => row.join("")), depth: tones };
    }

    const height = cells.length;
    const width = cells[0].length;
    const cx = (width - 1) / 2;
    const cy = (height - 1) / 2;
    laws.forEach((law, index) => {
      const glyph = String((law?.glyph) || "").charAt(0);
      if (!/^[\x20-\x7e]$/.test(glyph)) return;
      const angle = (-Math.PI / 2) + ((Math.PI * 2 * index) / laws.length);
      const col = halfUp(cx + (Math.cos(angle) * width * 0.47));
      const row = halfUp(cy + (Math.sin(angle) * height * 0.45));
      if (row < 0 || row >= height || col < 0 || col >= cells[row].length) return;
      if (cells[row][col] !== " ") return;
      cells[row][col] = glyph;
      if (tones[row] && col < tones[row].length) tones[row][col] = 1;
    });
    return { lines: cells.map((row) => row.join("")), depth: tones };
  }

  function createView(canvas, options) {
    const opts = options || {};
    const env = opts.env || root;
    const contract = opts.contract || env.MASTER_FACE_CONTRACT;
    activeContract = contract;
    const engine = build(contract);
    const laws = Array.isArray(opts.laws) ? opts.laws
      : (env.MASTER_FACE_LAW_FIELD && Array.isArray(env.MASTER_FACE_LAW_FIELD.laws) ? env.MASTER_FACE_LAW_FIELD.laws : []);
    const web = (contract.ascii && contract.ascii.web) || {};
    const budget = (contract.spatial && contract.spatial.budget) || {};
    const ROWS = num(web.rows, 44);
    const FONT = Array.isArray(web.font) ? web.font : [9, 20];
    const TONE = Array.isArray(web.tone) ? web.tone : [0.45, 0.75, 1.0];
    const ctx = canvas.getContext("2d");
    if (!ctx) return null;

    const view = {
      engine,
      cols: 0,
      rows: 0,
      cellW: 0,
      rowH: 0,
      lastText: "",
      lastAt: -Infinity,
      // Pointer drag adds a stable pose offset without creating another frame loop.
      turnOffset: 0.0,
    };

    const style = () => (env.getComputedStyle ? env.getComputedStyle(env.document.documentElement) : null);
    const mono = () => {
      const s = style();
      const family = s?.getPropertyValue("--font-mono").trim();
      return family || "ui-monospace, monospace";
    };

    // --face-fg resolves to whatever the theme made it (oklch, color-mix); an element's
    // computed colour is always rgb(), which a canvas accepts everywhere.
    let probe = null;
    const faceColor = () => {
      if (env.matchMedia && env.matchMedia("(forced-colors: active)").matches) return "CanvasText";
      if (!probe) {
        probe = env.document.createElement("span");
        probe.setAttribute("aria-hidden", "true");
        probe.style.cssText = "position:absolute;visibility:hidden;pointer-events:none;color:var(--face-fg, currentColor)";
        env.document.body.appendChild(probe);
      }
      return env.getComputedStyle(probe).color || "CanvasText";
    };

    function resize() {
      const dpr = Math.min(env.devicePixelRatio || 1, num(budget.max_device_pixel_ratio, 2));
      const cssW = Math.max(1, canvas.clientWidth || env.innerWidth || 1);
      const cssH = Math.max(1, canvas.clientHeight || env.innerHeight || 1);
      canvas.width = Math.floor(cssW * dpr);
      canvas.height = Math.floor(cssH * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const size = clamp(Math.floor(cssH / (1.2 * ROWS)), FONT[0], FONT[1]);
      view.family = mono();
      ctx.font = `400 ${size}px ${view.family}`;
      view.fontSize = size;
      view.cellW = ctx.measureText("M").width || size * 0.6;
      view.rowH = view.cellW * engine.ASPECT;
      view.cssW = cssW;
      view.cssH = cssH;
      view.cols = Math.floor(cssW / view.cellW);
      view.rows = Math.floor(cssH / view.rowH);
      view.lastText = "";
    }
    resize();

    function paintLines(lines, depth, forced) {
      ctx.clearRect(0, 0, view.cssW, view.cssH);
      const x0 = Math.floor((view.cssW - (view.cols * view.cellW)) / 2);
      const y0 = Math.floor((view.cssH - (view.rows * view.rowH)) / 2);
      ctx.textBaseline = "middle";
      ctx.fillStyle = faceColor();
      for (let tone = 0; tone < 3; tone += 1) {
        ctx.globalAlpha = forced ? 1 : TONE[tone];
        ctx.font = `${tone === 2 ? 700 : 400} ${view.fontSize}px ${view.family}`;
        for (let r = 0; r < lines.length; r += 1) {
          const row = lines[r];
          let text = "";
          let any = false;
          for (let c = 0; c < row.length; c += 1) {
            if (row[c] !== " " && (depth ? depth[r][c] : 1) === tone) { text += row[c]; any = true; } else text += " ";
          }
          if (any) ctx.fillText(text, x0, y0 + (r * view.rowH) + (view.rowH / 2));
        }
      }
      ctx.globalAlpha = 1;
    }

    // Draws one frame for the page's state at now (milliseconds). Answers whether it
    // painted; a frame earlier than the budget's rate, or identical to the last, does not.
    view.draw = function draw(now, input) {
      const state = engine.STATES.indexOf(input.state) >= 0 ? input.state : "idle";
      const calm = state === "idle" || state === "sleeping" || state === "ready";
      const fps = input.reduced ? num(budget.reduced_motion_fps, 8) : num(calm ? budget.idle_fps : budget.active_fps, 24);
      if (now - view.lastAt < 1000 / fps) return false;
      view.lastAt = now;
      const t = now / 1000;
      // The mask's mix is remembered from the moment the state last changed.
      if (state !== view.maskState) { view.maskState = state; view.maskSince = t; view.maskFrom = view.maskMix || 0.0; }
      const look = engine.lookFor({ state, t, level: input.level, viseme: input.viseme, shapes: input.shapes, reduced: input.reduced, session: input.session, since: view.maskSince, from: view.maskFrom });
      look.turn = (rotationEnabled ? look.turn : 0.0) + view.turnOffset;
      view.maskMix = look.mix;
      const out = engine.frame({ rows: view.rows, cols: view.cols, state, look, chars: activeChars(contract), mode: activeInkMode(contract) });
      const field = lawFieldVisible ? paintLawField(out.lines, out.depth, laws) : { lines: out.lines, depth: out.depth };
      const text = field.lines.join("\n");
      if (text === view.lastText) return false;
      view.lastText = text;
      paintLines(field.lines, field.depth, env.matchMedia && env.matchMedia("(forced-colors: active)").matches);
      return true;
    };

    view.resize = resize;
    if (env.ResizeObserver) new env.ResizeObserver(() => resize()).observe(canvas);
    else env.addEventListener("resize", resize, { passive: true });
    return view;
  }

  const faceQuery = new URLSearchParams(root.location?.search || "");
  function cleanCustomChars(value) {
    const chars = Array.from(String(value || ""))
      .filter((char) => char.charCodeAt(0) >= 32 && char.charCodeAt(0) <= 126)
      .slice(0, 32)
      .join("");
    return chars.length >= 2 ? chars : null;
  }
  let activeContract = root.MASTER_FACE_CONTRACT || null;
  let selectedRamp = faceQuery.get("face_ramp") || "";
  let customChars = cleanCustomChars(faceQuery.get("face_chars"));
  const requestedInk = faceQuery.get("face_ink");
  let selectedMode = requestedInk === "dark" || requestedInk === "light" ? requestedInk : null;
  let rotationEnabled = faceQuery.get("face_rotate") !== "0";
  let orbitTarget = null;
  let orbitPointerId = null;
  let orbitLastX = 0;
  let overlayCanvas = null;
  let overlayView = null;
  let glyphMode = false;

  function rampsFor(contract = activeContract) {
    const ascii = contract?.ascii || {};
    return ascii.ramps && Object.keys(ascii.ramps).length
      ? ascii.ramps
      : { sculpt: ascii.chars || " .:;=*%#@" };
  }

  function activeRampName(contract = activeContract) {
    const ramps = rampsFor(contract);
    const names = Object.keys(ramps);
    if (names.includes(selectedRamp)) return selectedRamp;
    return names.includes("sculpt") ? "sculpt" : (names[0] || "sculpt");
  }

  function activeChars(contract = activeContract) {
    const ascii = contract?.ascii || {};
    return customChars || rampsFor(contract)[activeRampName(contract)] || ascii.chars || " .:;=*%#@";
  }

  function activeInkMode(contract = activeContract) {
    const ascii = contract?.ascii || {};
    return selectedMode || (ascii.mode === "light" ? "light" : "dark");
  }

  function applyInkMode() {
    const doc = root.document;
    if (!doc) return;
    const light = activeInkMode() === "light";
    // "light" reverses the ASCII tone ramp. Filtering the canvas as well would
    // invert it twice and recolour the unrelated WebGL face and particle field.
    if (overlayCanvas?.style) overlayCanvas.style.filter = "";
    if (doc.documentElement?.dataset) doc.documentElement.dataset.faceInk = light ? "light" : "dark";
    if (overlayView) overlayView.lastText = "";
  }

  function refreshControls() {
    const doc = root.document;
    if (doc?.documentElement?.dataset) {
      doc.documentElement.dataset.faceRamp = customChars ? "custom" : activeRampName();
      doc.documentElement.dataset.faceRotation = rotationEnabled ? "running" : "paused";
    }
    applyInkMode();
    if (overlayView) overlayView.lastText = "";
    update(root.performance ? root.performance.now() : Date.now());
  }

  function setRamp(name) {
    if (!Object.prototype.hasOwnProperty.call(rampsFor(), name)) return false;
    selectedRamp = name;
    customChars = null;
    refreshControls();
    return true;
  }

  function cycleRamp() {
    const names = Object.keys(rampsFor());
    if (!names.length) return false;
    const current = activeRampName();
    const index = names.indexOf(current);
    return setRamp(names[(index + 1 + names.length) % names.length]);
  }

  function setInkMode(mode) {
    if (mode !== "dark" && mode !== "light") return false;
    selectedMode = mode;
    refreshControls();
    return true;
  }

  function setRotation(enabled) {
    rotationEnabled = !!enabled;
    refreshControls();
    return rotationEnabled;
  }

  // The ASCII layer ignores pointer input visually, so orbit attaches to the
  // real face canvas underneath it. Pointer capture keeps a drag continuous
  // when the pointer leaves the canvas; ending a drag never sends a chat action.
  function bindOrbitTarget(target) {
    if (orbitTarget === target) return;
    if (orbitTarget) {
      orbitTarget.removeEventListener("pointerdown", orbitStart);
      orbitTarget.removeEventListener("pointermove", orbitMove);
      orbitTarget.removeEventListener("pointerup", orbitEnd);
      orbitTarget.removeEventListener("pointercancel", orbitEnd);
      orbitTarget.removeEventListener("lostpointercapture", orbitEnd);
    }
    orbitTarget = target || null;
    orbitPointerId = null;
    if (!orbitTarget?.addEventListener) return;
    orbitTarget.addEventListener("pointerdown", orbitStart);
    orbitTarget.addEventListener("pointermove", orbitMove);
    orbitTarget.addEventListener("pointerup", orbitEnd);
    orbitTarget.addEventListener("pointercancel", orbitEnd);
    orbitTarget.addEventListener("lostpointercapture", orbitEnd);
  }

  function orbitStart(event) {
    if (event.isPrimary === false || (event.pointerType === "mouse" && event.button !== 0)) return;
    orbitPointerId = event.pointerId;
    orbitLastX = Number(event.clientX) || 0;
    try { orbitTarget?.setPointerCapture?.(event.pointerId); } catch (_) { /* capture is optional */ }
  }

  function orbitMove(event) {
    if (orbitPointerId === null || event.pointerId !== orbitPointerId || !overlayView) return;
    const x = Number(event.clientX) || 0;
    const delta = x - orbitLastX;
    orbitLastX = x;
    if (!delta) return;
    overlayView.turnOffset += delta * 0.01;
    overlayView.lastText = "";
    // The existing face clock will render the changed pose on its next tick.
  }

  function orbitEnd(event) {
    if (orbitPointerId === null || (event.pointerId !== undefined && event.pointerId !== orbitPointerId)) return;
    orbitPointerId = null;
  }

  function activeState() {
    if (!root.document || !root.document.body) return "idle";
    const body = root.document.body;
    const raw = String(body.dataset.mode || body.dataset.state || "idle").toLowerCase();
    const contract = root.MASTER_FACE_CONTRACT || {};
    const aliases = (contract.state && contract.state.mode_aliases) || contract.mode_aliases || {};
    return aliases[raw] || raw;
  }

  function update(now) {
    if (!root.document || !root.document.body) return false;
    const doc = root.document;
    if (doc.getElementById("face-2d-fallback")) {
      if (overlayCanvas) overlayCanvas.style.display = "none";
      return false;
    }
    const faceCanvas = doc.getElementById("face");
    if (!faceCanvas) return false;
    bindOrbitTarget(faceCanvas);

    if (!overlayCanvas || !overlayCanvas.isConnected) {
      overlayCanvas = doc.getElementById("master-face-ascii");
      if (!overlayCanvas) {
        overlayCanvas = doc.createElement("canvas");
        overlayCanvas.id = "master-face-ascii";
        overlayCanvas.className = "master-face-ascii-layer";
        overlayCanvas.setAttribute("aria-hidden", "true");
        overlayCanvas.setAttribute("role", "presentation");
        overlayCanvas.style.pointerEvents = "none";
        doc.body.appendChild(overlayCanvas);
      }
      overlayView = createView(overlayCanvas, { env:root, contract:root.MASTER_FACE_CONTRACT });
      applyInkMode();
    }
    if (!overlayView) return false;
    overlayCanvas.style.display = "";
    const reduced = !!(root.matchMedia && root.matchMedia("(prefers-reduced-motion: reduce)").matches)
      || doc.body.dataset.reducedMotion === "1";
    return overlayView.draw(Number.isFinite(now) ? now : (root.performance ? root.performance.now() : Date.now()),
      { state:activeState(), reduced, session: doc.body.dataset.session || doc.body.dataset.conversation });
  }

  function resize() {
    if (overlayView) overlayView.resize();
  }

  function setLawField(enabled) {
    const config = root.MASTER_FACE_LAW_FIELD || {};
    lawFieldVisible = config.enabled === false ? false : !!enabled;
    if (overlayView) overlayView.lastText = "";
    return lawFieldVisible;
  }

  function setGlyphMode(enabled) {
    glyphMode = !!enabled;
    if (root.document && root.document.body) {
      if (glyphMode) root.document.body.dataset.faceAscii = "1";
      else delete root.document.body.dataset.faceAscii;
    }
    if (overlayCanvas) overlayCanvas.style.opacity = glyphMode ? "0.96" : "";
    if (overlayView) overlayView.lastText = "";
  }

  function onKeydown(event) {
    if (!root.document || event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey) return;
    const target = event.target;
    if (target && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))) return;

    const field = root.MASTER_FACE_LAW_FIELD || {};
    const pressed = String(event.key).toLowerCase();
    const status = root.document.getElementById("master-face-ascii-status")
      || root.document.getElementById("ui-status");
    const lawKey = String(field.toggle_key || "l").toLowerCase();
    if (pressed === lawKey) {
      setLawField(!lawFieldVisible);
      const legend = Array.isArray(field.laws)
        ? field.laws.map((law) => {
          const glyph = String(law.glyph || "").slice(0, 1);
          const name = String(law.id || "").toLowerCase().split("_")[0];
          return glyph && name ? `${glyph} ${name}` : "";
        }).filter(Boolean).join(", ")
        : "";
      if (status) status.textContent = lawFieldVisible
        ? `Constitutional law glyphs visible${legend ? ` in priority order: ${legend}` : ""}`
        : "Constitutional law glyphs hidden";
      // The regular face loop repaints changed law glyphs without creating another canvas.
      return;
    }

    if (pressed === "r") {
      setRotation(!rotationEnabled);
      if (status) status.textContent = rotationEnabled ? "3D face rotation resumed" : "3D face rotation paused";
      return;
    }
    if (pressed === "m") {
      setInkMode(activeInkMode() === "light" ? "dark" : "light");
      if (status) status.textContent = activeInkMode() === "light" ? "Reverse ASCII relief" : "Standard ASCII relief";
      return;
    }
    if (pressed === "c") {
      if (cycleRamp() && status) {
        status.textContent = `3D ASCII ramp: ${customChars ? "custom" : activeRampName()}`;
      }
      return;
    }

    const overlayKey = String(field.overlay_toggle_key || "v").toLowerCase();
    if (pressed !== overlayKey) return;
    setGlyphMode(!glyphMode);
    if (status) status.textContent = glyphMode ? "ASCII face mode enabled" : "ASCII face overlay enabled";
    update(root.performance ? root.performance.now() : Date.now());
  }
  const api = { build, createView, kbSum, paintLawField, update, resize, setLawField, setGlyphMode, setRamp, setInkMode, setRotation };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (root?.document) {
    root.MASTER_FACE_ASCII = Object.freeze(api);
    root.addEventListener("keydown", onKeydown);
    root.dispatchEvent(new root.CustomEvent("master:face-ascii-ready"));
  }
})(typeof window !== "undefined" ? window : globalThis);
