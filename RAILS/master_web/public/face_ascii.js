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
    const ascii = (contract && contract.ascii) || {};
    const morphology = (contract && contract.spatial && contract.spatial.morphology) || {};
    if (!ascii.dither || !ascii.motion) throw new Error("face contract has no ascii block");

    // ---- Face::Glyphs -------------------------------------------------------
    const ASPECT = num(ascii.aspect, 2.0);
    const DITHER = ascii.dither;
    const DITHER_GAIN = ascii.dither_gain;
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

    // The ramp index for a tone, nudged by the integer dither matrix fixed in screen space.
    function index(tone, size, col, row) {
      const threshold = 0.5 + ((((DITHER[row % 4][col % 4] + 0.5) / 16.0) - 0.5) * DITHER_GAIN);
      return clamp(Math.floor((tone * (size - 1)) + threshold), 0, size - 1);
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
    const THRESHOLD = 0.08;
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
    const DEPTH_RATIO = 1.10 * JAW_PROJECTION * JAW_SOFTENING * MASTICATORY_SCALE;
    const RELIEF = 0.20 * NASAL_PROJECTION;
    const BACK_LIGHT = 0.28;
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

    // The head for a window of rows x cols cells: [x, y, z, brightness, zone] points.
    function head(rows, cols) {
      const dotsWide = cols * 2;
      const dotsHigh = rows * 4;
      const faceDots = Math.min(dotsWide, dotsHigh * 0.62) * 0.55;
      const density = clamp(Math.round(faceDots * 2.0), 40, 160);
      const latticeRows = Math.round(density * 66 / 52.0);
      const mask = [];
      for (let row = 0; row < latticeRows; row += 1) {
        const shift = row % 2 === 1 ? 0.5 : 0.0;
        const v = (row + 0.5) / latticeRows;
        const points = [];
        for (let col = 0; col < density; col += 1) {
          const u = (col + shift + 0.5) / density;
          const l = lum(u, v);
          if (l >= THRESHOLD) points.push([((u * 2) - 1) * SPREAD, l]);
        }
        if (points.length) mask.push([-((v * 2) - 1) * SPREAD, points]);
      }
      let xmin = Infinity, xmax = -Infinity;
      mask.forEach((r) => r[1].forEach((p) => { if (p[0] < xmin) xmin = p[0]; if (p[0] > xmax) xmax = p[0]; }));
      const ys = mask.map((r) => r[0]);
      const centre = [(xmax + xmin) / 2, (Math.max(...ys) + Math.min(...ys)) / 2];
      const spacing = mask.length > 1 ? Math.abs(mask[0][0] - mask[1][0]) : 0.05;
      const out = [];
      const cells = [];
      mask.forEach((r) => {
        const y = r[0];
        const pts = r[1];
        let reach = 0;
        pts.forEach((p) => { const d = Math.abs(p[0] - centre[0]); if (d > reach) reach = d; });
        const hw = reach + (spacing / 2);
        const depth = hw * DEPTH_RATIO * CRANIUM_SCALE;
        const count = Math.max(Math.round(Math.PI * (hw + depth) / 2 / spacing), 2);
        const fronts = [];
        pts.forEach((p) => {
          const x = p[0];
          const l = p[1];
          const localY = (y - centre[1]) * FACIAL_VERTICALIZATION;
          const upper = clamp((localY + 0.38) / 0.80, 0.0, 1.0);
          const widthScale = LOWER_FACE_SCALE + ((UPPER_FACE_SCALE - LOWER_FACE_SCALE) * upper);
          const localX = (x - centre[0]) * widthScale;
          const across = clamp(localX / (hw * CRANIAL_WIDTH), -1.0, 1.0);
          const z = (hw * DEPTH_RATIO * CRANIUM_SCALE * Math.sqrt(1 - (across * across))) + ((l - 0.5) * RELIEF);
          const zone = zoneAt(x, y);
          out.push([localX, localY, z, l, zone]);
          fronts.push([x, l, zone]);
        });
        // Kept for maskSource, which places these same lattice points again.
        cells.push([y, hw, count, fronts]);
        for (let i = 1; i < count; i += 1) {
          const angle = (Math.PI / 2) + (Math.PI * i / count);
          out.push([hw * Math.sin(angle), y - centre[1], depth * Math.cos(angle), BACK_LIGHT, SKIN_ZONE]);
        }
      });
      return { points: out, features: true, cells, centre };
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

    // The head's lattice under a mask at a mix: the head itself at 0.
    function maskSource(headObj, name, amount) {
      if (name === null || name === undefined || !(amount > 0.0)) return headObj;
      const p = morph(NEUTRAL, maskParams(name), amount);
      const depthRatio = 1.10 * p.jaw_projection * p.jaw_softening * p.masticatory_scale;
      const relief = 0.20 * p.nasal_projection;
      const cy = headObj.centre[1];
      const cx = headObj.centre[0];
      const beak = (x, y) => {
        const t = (p.beak_top - y) / p.beak_length;
        if (t < 0) return 0.0;
        const past = (t - 1.0) * p.beak_length / 0.04;
        const taper = t <= 1.0 ? smoothstep(t) : Math.exp(-(past * past));
        const side = x / p.beak_width;
        return p.beak_projection * taper * Math.exp(-(side * side));
      };
      const bumps = (x, y, zone) => {
        let lift = 0.0;
        if (p.beak_projection > 0) lift += beak(x, y);
        if (p.brow_ridge > 0) {
          const up = (y - p.brow_y) / p.brow_height;
          const across = x / p.brow_width;
          lift += p.brow_ridge * Math.exp(-(up * up)) * Math.exp(-(across * across * across * across));
        }
        if (p.socket_depth > 0 && zone >= 1 && zone <= 2) lift -= p.socket_depth * (zone === 1 ? 1.0 : 0.4);
        return lift;
      };
      const points = [];
      headObj.cells.forEach(([y, hw, count, fronts]) => {
        fronts.forEach(([x, l, zone]) => {
          const baseY = (y - cy) * p.facial_verticalization;
          const upper = clamp((baseY + 0.38) / 0.80, 0.0, 1.0);
          const localX = (x - cx) * (p.lower_face_scale + ((p.upper_face_scale - p.lower_face_scale) * upper));
          const across = clamp(localX / (hw * p.cranial_width), -1.0, 1.0);
          let z = ((hw * depthRatio * p.cranium_scale * Math.sqrt(1 - (across * across))) * p.depth_scale) + ((l - 0.5) * relief * p.relief);
          z += bumps(localX, baseY, zone);
          points.push([localX * p.width, baseY * p.face_length, z, l + ((p.flat_brightness - l) * p.flatten), zone]);
        });
        const depth = hw * depthRatio * p.cranium_scale;
        for (let i = 1; i < count; i += 1) {
          const angle = (Math.PI / 2) + (Math.PI * i / count);
          points.push([hw * Math.sin(angle) * p.width, (y - cy) * p.face_length, depth * Math.cos(angle) * p.depth_scale, BACK_LIGHT, 0]);
        }
      });
      let reach = 0;
      headObj.cells.forEach((cell) => { if (cell[1] > reach) reach = cell[1]; });
      reach *= p.width;
      const above = p.halo > 0 ? (p.halo_rise * p.halo) + ((halfUp(p.halo_rows) - 1) * p.halo_gap) : 0.0;
      const aside = p.disc > 0 ? reach + (p.disc_offset * p.disc) + (p.disc_radius * p.disc) : 0.0;
      return { points, features: true, params: p, margins: [above, aside] };
    }

    // ---- Face::Mesh ---------------------------------------------------------
    const MESH_BRIGHTNESS = 0.8;
    const MESH_ACROSS = 90;

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

    // An ASCII STL or an OBJ read into triangles and sampled into points, centred on its
    // bounding box; y is up (pass up: "z" for the CAD convention).
    function mesh(text, up) {
      const solid = /^\s*solid\b/im.test(text) && /^\s*vertex\b/im.test(text);
      let triangles = solid ? meshStl(text) : meshObj(text);
      if (!triangles.length) throw new Error("mesh: no triangles found");
      if (up === "z") triangles = triangles.map((t) => t.map((p) => [p[0], p[2], -p[1]]));
      const flat = triangles.flat();
      const mid = [0, 1, 2].map((a) => { const [lo, hi] = minMax(flat.map((p) => p[a])); return (lo + hi) / 2.0; });
      const centred = triangles.map((t) => t.map((p) => [p[0] - mid[0], p[1] - mid[1], p[2] - mid[2]]));
      const longest = Math.max(...[0, 1, 2].map((a) => { const [lo, hi] = minMax(flat.map((p) => p[a])); return hi - lo; }));
      const step = longest / MESH_ACROSS;
      const points = [];
      centred.forEach(([a, b, c]) => {
        const longestEdge = Math.max(...[[a, b], [b, c], [c, a]].map(([p, q]) =>
          Math.sqrt(kbSum([0, 1, 2].map((k) => (p[k] - q[k]) * (p[k] - q[k]))))));
        const n = clamp(Math.ceil(longestEdge / step), 1, 400);
        for (let i = 0; i <= n; i += 1) {
          for (let j = 0; j <= n - i; j += 1) {
            const u = i / n;
            const v = j / n;
            const w = 1.0 - u - v;
            const p = [0, 1, 2].map((k) => (a[k] * w) + (b[k] * u) + (c[k] * v));
            points.push([p[0], p[1], p[2], MESH_BRIGHTNESS, 0]);
          }
        }
      });
      return { points, features: false, triangles: centred };
    }

    // ---- Face::Ascii --------------------------------------------------------
    const lightRaw = ascii.light;
    const lightLen = Math.sqrt((lightRaw[0] * lightRaw[0]) + (lightRaw[1] * lightRaw[1]) + (lightRaw[2] * lightRaw[2]));
    const LIGHT = [lightRaw[0] / lightLen, lightRaw[1] / lightLen, lightRaw[2] / lightLen];
    const CAMERA = ascii.camera;
    const FIT = ascii.fit;
    const SPLAT = ascii.splat;
    const CREASE = ascii.crease;
    const EDGE = ascii.edge_gradient;
    const HOLLOW = ascii.hollow;
    const GAP = Math.trunc(ascii.gap);
    const SEE_THROUGH = ascii.see_through;
    const BASE = ascii.shade.base;
    const GAIN = ascii.shade.gain;
    const PAINT = ascii.shade.paint;
    const CEILING = ascii.shade.ceiling;
    const NEAR = ascii.depth.near;
    const FAR = ascii.depth.far;
    const OCCLUSION = ascii.occlusion;
    const FEATURE = ascii.features;
    const MIN_ROWS = ascii.min_rows;
    const MIN_COLS = ascii.min_cols;
    const SHUT = 0.5;

    const mean = (list, axis) => kbSum(list.map((p) => p[axis])) / list.length;
    const meanPoint = (list) => (list.length ? [0, 1, 2].map((a) => mean(list, a)) : null);
    const nearest = (list, x, y) => minBy(list, (p) => ((p[0] - x) * (p[0] - x)) + ((p[1] - y) * (p[1] - y)));

    // The eyes, brows, nose and mouth anchors, found in the points by their zone.
    function findAnchors(points) {
      const eyes = [];
      [-1, 1].forEach((side) => {
        const zone = points.filter((p) => p[4] >= 1 && p[4] <= 2 && Math.sign(p[0]) === side);
        if (!zone.length) return;
        const eye = meanPoint(zone.filter((p) => p[4] === 2)) || meanPoint(zone);
        const far = maxBy(zone.map((p) => p[0]), (x) => Math.abs(x - eye[0]));
        const reach = Math.abs(far - eye[0]) * 0.8;
        eyes.push({ left: nearest(zone, eye[0] - reach, eye[1]), right: nearest(zone, eye[0] + reach, eye[1]), pupil: eye });
      });
      const mouth = points.filter((p) => p[4] === MOUTH_ZONE);
      if (eyes.length < 2 || !mouth.length) return null;
      const mx = minMax(mouth.map((p) => p[0]));
      const my = mean(mouth, 1);
      const skin = points.filter((p) => p[4] === 0 && Math.abs(p[0]) < 0.05 && p[2] > 0);
      const eyeY = kbSum(eyes.map((e) => e.pupil[1])) / 2.0;
      const between = skin.filter((p) => p[1] < eyeY && p[1] > my + 0.05);
      const tip = maxBy(between, (p) => p[2]);
      if (!tip || !skin.length) return null;
      return {
        eyes,
        mouth: { left: nearest(mouth, mx[0], my), right: nearest(mouth, mx[1], my), centre: meanPoint(mouth) },
        bridge: nearest(skin, 0.0, eyeY),
        tip,
      };
    }

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
      constructor(source, rows, cols, options) {
        const opts = options || {};
        this.rows = rows;
        this.cols = cols;
        this.w = cols;
        this.h = rows * 2;
        this.ramp = ramp(opts.chars, opts.mode);
        this.points = source.points.map((p) => [p[0], p[1], p[2], p[3], p[4]]);
        const ysRaw = this.points.map((p) => p[1]);
        const [ylo, yhi] = minMax(ysRaw);
        const margins = source.margins || [0.0, 0.0];
        const above = margins[0];
        const lift = (ylo + yhi + above) / 2.0;
        this.points.forEach((p) => { p[1] -= lift; });
        let reach = 0;
        this.points.forEach((p) => { const d = hypot(p[0], p[2]); if (d > reach) reach = d; });
        reach = Math.max(reach, margins[1]);
        const [slo, shi] = minMax(this.points.map((p) => p[1]));
        const span = shi - slo + above;
        this.scale = Math.min(((this.w / 2.0) - 1) / reach, (this.h - 2) / span) * FIT;
        this.anchors = source.features ? findAnchors(this.points) : null;
        this.mask = source.params || null;
        if (this.mask && this.anchors) {
          this.top = maxBy(this.points.map((p) => p[1]), (v) => v);
          this.side = maxBy(this.points.map((p) => Math.abs(p[0])), (v) => v);
        }
      }

      // The points as fitted (x, y, z, brightness), which the fixtures fingerprint: the
      // digest is a sha256 of them formatted by Ruby, whose %.4f rounds near-ties its own way.
      fitted() {
        return this.points.map((p) => p.slice(0, 4));
      }

      render(look, state) {
        this.turn(look);
        this.buffer();
        this.frame = new Frame(
          Array.from({ length: this.rows }, () => new Array(this.w).fill(" ")),
          Array.from({ length: this.rows }, () => new Array(this.w).fill(1)),
        );
        for (let r = 0; r < this.rows; r += 1) for (let c = 0; c < this.w; c += 1) this.cell(c, r);
        if (this.anchors) this.drawFeatures(look, state || "idle");
        return this.frame;
      }

      // A source-space point in sub-pixels, and its depth in the same units.
      project(x, y, z) {
        const rx = (x * this.cy) + (z * this.sy);
        let rz = (-x * this.sy) + (z * this.cy);
        const ry = (y * this.cp) - (rz * this.sp);
        rz = (y * this.sp) + (rz * this.cp);
        const k = this.gain * this.camera / (this.camera - rz);
        return [this.w / 2.0 + (((rx * this.cr) - (ry * this.sr)) * k), this.rows - (((rx * this.sr) + (ry * this.cr)) * k) - this.bob, rz * this.scale];
      }

      hidden(px, py, depth, slack) {
        const x = Math.floor(px);
        const y = Math.floor(py);
        if (!(x >= 0 && x <= this.w - 1 && y >= 0 && y <= this.h - 1)) return true;
        return this.zb[(y * this.w) + x] > depth + OCCLUSION + (slack || 0.0);
      }

      turn(look) {
        const angles = [look.yaw + look.turn, look.pitch, look.roll];
        this.cy = Math.cos(angles[0]); this.sy = Math.sin(angles[0]);
        this.cp = Math.cos(angles[1]); this.sp = Math.sin(angles[1]);
        this.cr = Math.cos(angles[2]); this.sr = Math.sin(angles[2]);
        this.camera = CAMERA / look.dolly;
        this.gain = this.scale * look.scale;
        this.bob = look.bob * this.scale;
      }

      buffer() {
        const n = this.w * this.h;
        this.zb = new Float64Array(n).fill(NONE);
        this.bb = new Float64Array(n);
        for (let i = 0; i < this.points.length; i += 1) {
          const pt = this.points[i];
          const [px, py, depth] = this.project(pt[0], pt[1], pt[2]);
          const ix = Math.floor(px);
          const iy = Math.floor(py);
          for (let s = 0; s < SPLAT.length; s += 1) {
            const qx = ix + SPLAT[s][0];
            const qy = iy + SPLAT[s][1];
            if (!(qx >= 0 && qx < this.w && qy >= 0 && qy < this.h)) continue;
            const at = (qy * this.w) + qx;
            if (!(depth > this.zb[at])) continue;
            this.zb[at] = depth;
            this.bb[at] = pt[3];
          }
        }
        this.close();
        let lo = Infinity, hi = -Infinity;
        for (let i = 0; i < n; i += 1) {
          if (this.zb[i] > LIVE) { if (this.zb[i] < lo) lo = this.zb[i]; if (this.zb[i] > hi) hi = this.zb[i]; }
        }
        if (lo === Infinity) { lo = 0.0; hi = 0.0; }
        this.nearLo = lo;
        this.nearSpan = Math.max(hi - lo, 1.0);
        this.zs = this.smoothed(this.smoothed(this.zb));
      }

      // Seen near edge-on a surface is sampled sparsely, and the far side shows through
      // the gaps. A pixel with a nearer pixel on both sides within GAP pixels, along a
      // row or a column, takes the mean of the two nearest of them.
      close() {
        const fills = [];
        for (let y = 0; y < this.h; y += 1) {
          for (let x = 0; x < this.w; x += 1) {
            const i = (y * this.w) + x;
            const own = this.zb[i] + SEE_THROUGH;
            const pair = this.gap(i, 1, x, this.w, own) || this.gap(i, this.w, y, this.h, own);
            if (pair) fills.push([i, pair]);
          }
        }
        fills.forEach(([i, pair]) => {
          this.zb[i] = (this.zb[pair[0]] + this.zb[pair[1]]) / 2.0;
          this.bb[i] = (this.bb[pair[0]] + this.bb[pair[1]]) / 2.0;
        });
      }

      gap(i, stride, at, limit, own) {
        let lo = -1;
        let hi = -1;
        for (let d = 1; d <= GAP; d += 1) {
          const j = i - (stride * d);
          if (at - d >= 0 && this.zb[j] > own && (lo < 0 || this.zb[j] > this.zb[lo])) lo = j;
          const k = i + (stride * d);
          if (at + d < limit && this.zb[k] > own && (hi < 0 || this.zb[k] > this.zb[hi])) hi = k;
        }
        return lo >= 0 && hi >= 0 ? [lo, hi] : null;
      }

      // A 3x3 mean of the live neighbours, as a row sum then a column sum.
      smoothed(src) {
        const n = this.w * this.h;
        const sums = new Float64Array(n);
        const counts = new Int32Array(n);
        for (let i = 0; i < n; i += 1) {
          const x = i % this.w;
          for (let dx = -1; dx <= 1; dx += 1) {
            if (x + dx < 0 || x + dx >= this.w || src[i + dx] <= LIVE) continue;
            sums[i] += src[i + dx];
            counts[i] += 1;
          }
        }
        const out = new Float64Array(n).fill(NONE);
        for (let i = 0; i < n; i += 1) {
          if (!(src[i] > LIVE)) continue;
          const y = Math.floor(i / this.w);
          let sum = 0.0;
          let count = 0;
          for (let dy = -1; dy <= 1; dy += 1) {
            if (y + dy < 0 || y + dy >= this.h) continue;
            sum += sums[i + (dy * this.w)];
            count += counts[i + (dy * this.w)];
          }
          out[i] = sum / count;
        }
        return out;
      }

      live(x, y) { return x >= 0 && x < this.w && y >= 0 && y < this.h && this.zb[(y * this.w) + x] > LIVE; }

      // Smoothed depth with the pixel's own as stand-in off the head.
      z(x, y, own) { return this.live(x, y) ? this.zs[(y * this.w) + x] : own; }

      occupancy(x, y) {
        let n = 0;
        for (let dy = -2; dy <= 2; dy += 1) for (let dx = -2; dx <= 2; dx += 1) if (this.live(x + dx, y + dy)) n += 1;
        return n / 25.0;
      }

      cell(c, r) {
        const top = this.live(c, 2 * r);
        const bottom = this.live(c, (2 * r) + 1);
        if (!(top || bottom)) return;
        const ys = [];
        if (top) ys.push(2 * r);
        if (bottom) ys.push((2 * r) + 1);
        const edge = !(top && bottom)
          || !(this.live(c, (2 * r) - 1) && this.live(c, (2 * r) + 2))
          || [c - 1, c + 1].some((x) => !this.live(x, 2 * r) && !this.live(x, (2 * r) + 1));
        const glyph = edge ? this.silhouette(c, ys, top, bottom) : this.crease(c, ys);
        this.frame.chars[r][c] = glyph || this.shade(c, r, ys);
        this.frame.depth[r][c] = this.band(this.zb[(ys[ys.length - 1] * this.w) + c]);
      }

      band(depth) {
        const fraction = (depth - this.nearLo) / this.nearSpan;
        if (fraction >= NEAR) return 2;
        if (fraction <= FAR) return 0;
        return 1;
      }

      silhouette(c, ys, top, bottom) {
        let gx = 0.0;
        let gy = 0.0;
        ys.forEach((y) => {
          gx += this.occupancy(c + 1, y) - this.occupancy(c - 1, y);
          gy += this.occupancy(c, y + 1) - this.occupancy(c, y - 1);
        });
        if (hypot(gx, gy) < EDGE) return null;
        const glyph = line(gy, gx);
        return glyph === "-" ? level(top, bottom, gy < 0) : glyph;
      }

      crease(c, ys) {
        let xx = 0.0, yy = 0.0, xy = 0.0;
        ys.forEach((y) => {
          const own = this.zs[(y * this.w) + c];
          const here = own * 2;
          xx += (this.z(c + 2, y, own) + this.z(c - 2, y, own) - here) / 4.0;
          yy += (this.z(c, y + 2, own) + this.z(c, y - 2, own) - here) / 4.0;
          xy += (this.z(c + 2, y + 2, own) - this.z(c - 2, y + 2, own) - this.z(c + 2, y - 2, own) + this.z(c - 2, y - 2, own)) / 16.0;
        });
        xx /= ys.length;
        yy /= ys.length;
        xy /= ys.length;
        const dd = (xx - yy) / 2;
        const halfSpread = Math.sqrt((dd * dd) + (xy * xy));
        const mid = (xx + yy) / 2;
        if (Math.abs(mid) + halfSpread < CREASE) return null;
        const angle = 0.5 * Math.atan2(2 * xy, xx - yy);
        if (Math.abs(mid + halfSpread) >= Math.abs(mid - halfSpread)) return line(-Math.sin(angle), -Math.cos(angle));
        return line(-Math.cos(angle), Math.sin(angle));
      }

      shade(c, r, ys) {
        let nx = 0.0, ny = 0.0, bright = 0.0, hollow = 0.0;
        ys.forEach((y) => {
          const own = this.zs[(y * this.w) + c];
          nx -= (this.z(c + 2, y, own) - this.z(c - 2, y, own)) / 4.0;
          ny += (this.z(c, y + 2, own) - this.z(c, y - 2, own)) / 4.0;
          hollow += (this.z(c + 2, y, own) + this.z(c - 2, y, own) + this.z(c, y + 2, own) + this.z(c, y - 2, own) - (4 * own)) / 16.0;
          bright += this.bb[(y * this.w) + c];
        });
        nx /= ys.length;
        ny /= ys.length;
        bright /= ys.length;
        hollow /= ys.length;
        const length = Math.sqrt((nx * nx) + (ny * ny) + 1.0);
        const lumen = Math.max(((nx * LIGHT[0]) + (ny * LIGHT[1]) + LIGHT[2]) / length, 0.0);
        const tone = clamp(Math.min(((BASE + (GAIN * lumen)) * (1.0 - PAINT + (PAINT * bright))) - (HOLLOW * clamp(hollow, -0.4, 0.4)), CEILING), 0.0, 1.0);
        return this.ramp[index(tone, this.ramp.length, c, r)];
      }

      // ---- Face::Features ---------------------------------------------------
      cellOf(point, slack) {
        const [px, py, depth] = this.project(point[0], point[1], point[2]);
        return [px, py, depth, this.hidden(px, py, depth, slack)];
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
        this.rings = !!(mask && mask.ring >= MASK_TAKEOVER);
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
        const [px, py] = this.cellOf(eye.pupil);
        const span = Math.floor(Math.abs(rx - lx));
        const width = Math.min(span % 2 === 0 ? span + 1 : span, 9);
        const col = halfUp(px);
        const row = Math.floor(py / 2);
        if (width < 3) {
          this.put(col, row, this.look.eye_open < SHUT ? FEATURE.lid : FEATURE.pupil);
          return;
        }
        const left = col - half(width);
        if (this.look.eye_open < SHUT) {
          this.run(left, row, FEATURE.lid.repeat(width));
        } else {
          const inner = width - 2;
          const reach = half(inner);
          const glance = clamp(halfUp(this.look.gaze[0] * 14), -reach, reach);
          this.run(left, row, FEATURE.eye_open + " ".repeat(inner) + FEATURE.eye_close);
          this.put(col + glance, row, FEATURE.pupil);
        }
        if (!this.mask || this.mask.brow_line >= 0.5) this.run(left, row - 1, FEATURE.brow.repeat(width));
        if (this.mask && this.mask.brow_ridge >= BROW_MIN) this.run(left, row - 2, MASK_GLYPHS.brow_heavy.repeat(width));
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
        if (this.cellOf(eye.left)[3] && this.cellOf(eye.right)[3]) return;
        const [px, py] = this.cellOf(eye.pupil);
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
      if (input.reduced) {
        look.turn = 0.0; look.pitch = 0.0; look.roll = 0.0; look.scale = 1.0; look.dolly = 1.0; look.bob = 0.0; look.mix = 0.0;
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
      const key = `${rows}x${cols}`;
      let renderer = cache.get(key);
      if (!renderer) {
        if (cache.size >= 6) { cache.clear(); heads.clear(); }
        const built = head(rows, cols);
        heads.set(key, built);
        renderer = new Renderer(built, rows, cols, { chars: options.chars, mode: options.mode });
        cache.set(key, renderer);
      }
      // A morphed head is new every frame, so it is not kept.
      if (options.look.mix > 0) {
        renderer = new Renderer(maskSource(heads.get(key), options.look.mask, options.look.mix), rows, cols, { chars: options.chars, mode: options.mode });
      }
      const out = renderer.render(options.look, options.state);
      return { word: false, lines: out.chars.map((row) => row.join("")), depth: out.depth };
    }

    return {
      FPS, STATES, MIN_ROWS, MIN_COLS, ASPECT, DEFAULT_CHARS, MOTION,
      Glyphs: { line, level, ramp, index, halfUp },
      DepthMap: { lum },
      head,
      mesh,
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
      const glyph = String((law && law.glyph) || "").charAt(0);
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
    };

    const style = () => (env.getComputedStyle ? env.getComputedStyle(env.document.documentElement) : null);
    const mono = () => {
      const s = style();
      const family = s && s.getPropertyValue("--font-mono").trim();
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
      view.maskMix = look.mix;
      const out = engine.frame({ rows: view.rows, cols: view.cols, state, look, mode: contract.ascii.mode });
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

  let overlayCanvas = null;
  let overlayView = null;
  let glyphMode = false;

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
    if (!doc.getElementById("face")) return false;

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

    const overlayKey = String(field.overlay_toggle_key || "v").toLowerCase();
    if (pressed !== overlayKey) return;
    setGlyphMode(!glyphMode);
    if (status) status.textContent = glyphMode ? "ASCII face mode enabled" : "ASCII face overlay enabled";
    update(root.performance ? root.performance.now() : Date.now());
  }
  const api = { build, createView, kbSum, paintLawField, update, resize, setLawField, setGlyphMode };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (root && root.document) {
    root.MASTER_FACE_ASCII = Object.freeze(api);
    root.addEventListener("keydown", onKeydown);
    root.dispatchEvent(new root.CustomEvent("master:face-ascii-ready"));
  }
})(typeof window !== "undefined" ? window : globalThis);
