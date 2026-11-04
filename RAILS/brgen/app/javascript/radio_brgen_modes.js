// The operator's radio.brgen.no visualiser (pen, 2026-10-31), as data and one
// shader function: the three-tone gradient and the 22 parametric ring modes,
// simplest first. radio_brgen_tunnel.js draws them; this file is only what
// the pen decided, so a mode is added or retuned here and nowhere else.

// The operator's three-tone gradient (radio.brgen.no pen, 2026-10-31): deep
// slate blue, soft cyan-blue, muted teal, given in HSL there and converted
// once here. The pen runs it far to near as teal, cyan-blue, slate; a slow
// phase, lifted by the music, drifts the stops along the tube.
function fromHsl(h, s, l) {
  s /= 100
  l /= 100
  const f = (n) => {
    const k = (n + h / 30) % 12
    return l - s * Math.min(l, 1 - l) * Math.max(-1, Math.min(k - 3, 9 - k, 1))
  }
  return { r: f(0), g: f(8), b: f(4) }
}
export const INK_FAR = fromHsl(180, 30, 28)
export const INK_MID = fromHsl(190, 50, 38)
export const INK_NEAR = fromHsl(210, 40, 16)

// The operator's 22 ring modes, simplest first. Each is a radial offset in
// the pen's units (a 75-unit ring), drawn by ringShape in the vertex shader in
// this order; twist scales how fast the ring turns. Classic Tunnel adds
// nothing, so mode 0 is the tunnel as it always was.
export const MODES = [
{ name: "Classic Tunnel", twist: 1.0 }, { name: "Diagrid Tube", twist: 1.0 },
{ name: "Catenary Vaults", twist: 0.96 }, { name: "Ribbed Shell (Nervi)", twist: 1.02 },
{ name: "Hypar Ruled Surface", twist: 1.04 }, { name: "Lamella (Zollinger)", twist: 0.98 },
{ name: "Reciprocal Frame Helix", twist: 1.08 }, { name: "Girih Corridor", twist: 1.0 },
{ name: "Superellipse Gallery", twist: 0.94 }, { name: "Schwarz-P Slices", twist: 0.96 },
{ name: "Phyllotaxis Rib Vault", twist: 1.04 }, { name: "Kresling Origami", twist: 1.06 },
{ name: "Quasicrystal Moiré", twist: 1.01 }, { name: "Torus Knot Arcade", twist: 0.97 },
{ name: "Conformal Power Nave", twist: 0.92 }, { name: "Penrose Aperiodic", twist: 1.0 },
{ name: "Lissajous Nave", twist: 1.0 }, { name: "Superformula Bloom", twist: 0.92 },
{ name: "Hopf Fiber Arcade", twist: 1.05 }, { name: "Voronoi Drift", twist: 1.0 },
{ name: "PI3DETR Edges", twist: 1.02 }, { name: "Seek-CAD Generative", twist: 0.98 }
]

// wrap a keyboard step around the available modes without exposing array mutation.
export function modeAfterStep(current, step, count = MODES.length) {
  if (!Number.isInteger(current) || !Number.isInteger(step) || !Number.isInteger(count) || count < 1) {
    throw new RangeError("radio mode index, step and count must be integers; count must be positive")
  }
  return ((current + step) % count + count) % count
}


// ringShape for the vertex shader: the radial offset, in the pen's 75-unit
// ring, for angle th on ring i (0 at the far end to 125 at the near) at time t.
// GLSL ES 1.00 has no switch, so the modes are an if-ladder in MODES order.
// It reads uMode, uBass, uMid and uHigh, which the tunnel's shader declares.
export const RING_SHAPE_GLSL = `
const float TAU = 6.2831853;
const float PI = 3.1415927;
const float PHI = 1.6180340;

float coshf(float x) { return 0.5 * (exp(x) + exp(-x)); }

// The operator's 22 parametric rings: a radial offset in the pen's units for
// angle th on ring i (0..125, far to near) at time t. GLSL ES 1.00 has no
// switch, so the modes are an if-ladder in MODES order.
float ringShape(float th, float i, float t) {
  float m = uMode;
  if (m < 0.5) return 0.0;
  if (m < 1.5) {
    float d = 8.0 + floor(uHigh * 8.0);
    return (cos(d * th + t * 0.3) + cos(d * 0.5 * th - t * 0.2)) * 8.0;
  }
  if (m < 2.5) { float k = 0.9 + uBass * 0.4; return -coshf(k * (mod(th, TAU) - PI)) + coshf(k * PI); }
  if (m < 3.5) { float ribs = 12.0 + floor(uMid * 6.0); return max(0.0, cos(ribs * th + i * 0.03)) * 16.0 - 8.0; }
  if (m < 4.5) { float g = i * 0.01 - 0.6; return (cos(th) * g - sin(th) * g) * 28.0; }
  if (m < 5.5) { return sign(sin(th * 6.0 + i * 0.05)) * cos(th * 3.0 + t * 0.2) * 14.0; }
  if (m < 6.5) { float beams = 7.0 + floor(uMid * 5.0); return cos(beams * th + i * 0.07 + t * 0.3) * 12.0; }
  if (m < 7.5) {
    float s = 0.0;
    for (int n = 0; n < 10; n++) s += cos(th * (float(n) + 2.0) + i * 0.02 + t * 0.15);
    return s;
  }
  if (m < 8.5) {
    float n = 2.6 + uBass * 1.1;
    float r = pow(abs(cos(th)), n) + pow(abs(sin(th)), n);
    return (pow(max(r, 0.0001), -1.0 / n) - 1.0) * 28.0;
  }
  if (m < 9.5) { return (cos(th * 0.8) + cos(i * 0.06) + cos(t * 0.6)) * 6.0; }
  if (m < 10.5) { return (sin(th * PHI * 0.5 + i * 0.11) + sin(th + t * 0.25)) * 6.0 + sin(th * 2.0) * 4.0; }
  if (m < 11.5) {
    float folds = 8.0 + floor(uHigh * 4.0);
    return sin(folds * th + i * 0.05 + t * 0.3) * cos(th * 2.0) * 14.0;
  }
  if (m < 12.5) {
    float s = 0.0;
    for (int n = 0; n < 6; n++) {
      float a = TAU * float(n) / 6.0;
      s += cos(cos(a) * th * 3.0 + sin(a) * (t * 0.22 + i * 0.01));
    }
    return s / 6.0 * 12.0;
  }
  if (m < 13.5) {
    float pk = 2.0 + floor(uMid * 2.0);
    float qk = 3.0 + floor(uBass * 2.0);
    return cos(qk * th + t * 0.28) * 12.0 + sin(pk * th * 0.5 + i * 0.018) * 4.0;
  }
  if (m < 14.5) { float k = 0.9 + uBass * 0.6; return (pow(1.0 + 0.22 * sin(th * 2.0 + t * 0.18), k) - 1.0) * 26.0; }
  if (m < 15.5) {
    float s = sin(th * PHI * 3.0) + sin(th * PHI * 5.0);
    return (s * 0.6 + sign(sin(th * PHI * 2.0)) * 0.4) * 16.0;
  }
  if (m < 16.5) {
    float ax = 2.0 + floor(uMid * 3.0);
    float by = 3.0 + floor(uHigh * 3.0);
    return (sin(ax * th + t * 0.4) + sin(by * th + t * 0.24)) * 6.0;
  }
  if (m < 17.5) {
    float mm = 7.0 + floor(uHigh * 5.0);
    float r = pow(abs(cos(mm * th / 4.0)), 0.7) + pow(abs(sin(mm * th / 4.0)), 0.7);
    return (pow(max(r, 0.0001), -1.0 / 1.2) - 1.0) * 26.0;
  }
  if (m < 18.5) { float phi = t * 0.28 + i * 0.035; return sin(th + phi) * 10.0 + sin(2.0 * th + phi * 0.7) * 6.0; }
  if (m < 19.5) {
    float cells = 10.0 + floor(uMid * 8.0);
    float tt = mod(th, TAU) / TAU * cells;
    float frac = fract(tt);
    float stepv = mod(floor(tt), 2.0) > 0.5 ? 1.0 - frac : frac;
    return (stepv - 0.5) * 18.0 + sin(i * 0.05 + t * 0.2) * 3.0;
  }
  if (m < 20.5) { return (cos(th * 5.0 + i * 0.02) + sin((th + t * 0.1) * 3.0)) * (10.0 + uHigh * 8.0); }
  float r = sin(th * PHI + i * 0.05 + t * 0.15) * 12.0;
  if ((uBass + uMid + uHigh) / 3.0 > 0.5) r += cos(th * 4.0) * 6.0;
  return r;
}
`;

