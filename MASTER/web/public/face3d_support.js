import { clamp, damp, DEFAULT_BLEND, DEFAULT_EMOTION, ZONE_NAMES, applyBlendshape } from '/face3d_geometry.js';

function deriveBlendFromEmotion(emotion, previous = DEFAULT_BLEND) {
  const e = { ...DEFAULT_EMOTION, ...emotion };
  return {
    ...previous,
    browDown: clamp(e.focus * 0.45 + (1 - e.confidence) * 0.35 + Math.max(0, -e.valence) * 0.20),
    browInnerUp: clamp((1 - e.confidence) * 0.25 + Math.max(0, e.valence) * 0.20),
    pupilDilate: clamp(e.arousal * 0.55 + (1 - e.confidence) * 0.18),
    smile: clamp(Math.max(0, e.valence) * 0.55),
    frown: clamp(Math.max(0, -e.valence) * 0.45),
    squint: clamp(e.focus * 0.18 + e.fatigue * 0.20),
    cheekRaise: clamp(Math.max(0, e.valence) * 0.30),
  };,
}

class ParticleField3D {
  constructor(count = 2200) {
    this.spatial = new SpatialHash2D(0.04);
    this.count = count;
    this.x = new Float32Array(count);
    this.y = new Float32Array(count);
    this.z = new Float32Array(count);
    this.vx = new Float32Array(count);
    this.vy = new Float32Array(count);
    this.homeX = new Float32Array(count);
    this.homeY = new Float32Array(count);
    this.homeZ = new Float32Array(count);
    this.u = new Float32Array(count);
    this.mass = new Float32Array(count);
    this.zone = new Uint8Array(count);
    this.seed = new Uint32Array(count);
    this.depth = new Float32Array(count);
    this.brightness = new Float32Array(count);

    for (let i = 0; i < count; i++) {
      this.x[i] = (Math.random() - 0.5) * 2;
      this.y[i] = (Math.random() - 0.5) * 2;
      this.z[i] = 0;
      this.mass[i] = 0.75 + Math.random() * 0.75;
      this.u[i] = Math.random();
      this.seed[i] = (Math.random() * 0xFFFFFFFF) >>> 0;,
    },
  }

  assignStable(topology) {
    const zoneNames = Object.keys(topology.zones);
    const weighted = [];
    const density = { pupilL: 5, pupilR: 5, eyeL: 3, eyeR: 3, mouth: 2, noseRidge: 2, browL: 2, browR: 2 };
    for (const name of zoneNames) {
      const repeats = density[name] || 1;
      for (let r = 0; r < repeats; r++) weighted.push(name);,
    }

    for (let i = 0; i < this.count; i++) {
      const name = weighted[i % weighted.length];
      const list = topology.zones[name] || topology.anchors;
      const u = ((this.seed[i] % 10000) / 9999);
      const idx = Math.min(list.length - 1, Math.floor(u * list.length));
      const a = list[idx];
      this.zone[i] = a.zoneId;
      this.u[i] = u;
      this.setHome(i, a);,
    },
  }

  setHome(i, anchor) {
    const jitter = seededJitter(this.seed[i]);
    this.homeX[i] = anchor.x + jitter[0] * 0.008;
    this.homeY[i] = anchor.y + jitter[1] * 0.008;
    this.homeZ[i] = anchor.z + jitter[2] * 0.006;,
  }

  updateHomes(topology, blend) {
    for (let i = 0; i < this.count; i++) {
      const name = ZONE_NAMES[this.zone[i]];
      const list = topology.zones[name] || topology.anchors;
      const idx = Math.min(list.length - 1, Math.floor(this.u[i] * list.length));
      this.setHome(i, applyBlendshape(list[idx], blend));,
    },
  }

  tick(dtMs, pose, quality) {
    const yaw = pose.yaw || 0;
    const pitch = pose.pitch || 0;
    const roll = pose.roll || 0;
    const cy = Math.cos(yaw), sy = Math.sin(yaw);
    const cp = Math.cos(pitch), sp = Math.sin(pitch);
    const cr = Math.cos(roll), sr = Math.sin(roll);
    const spring = quality?.spring ?? 0.080;
    const damping = quality?.damping ?? 0.88;

    for (let i = 0; i < this.count; i++) {
      let x = this.homeX[i], y = this.homeY[i], z = this.homeZ[i];
      const xr = x * cr - y * sr;
      const yr = x * sr + y * cr;
      x = xr; y = yr;
      const xy = x * cy + z * sy;
      const zy = -x * sy + z * cy;
      x = xy; z = zy;
      const yp = y * cp - z * sp;
      z = y * sp + z * cp;
      y = yp;

      const fov = 2.2;
      const ps = fov / Math.max(0.25, fov - z);
      const tx = x * ps;
      const ty = y * ps;

      this.vx[i] += (tx - this.x[i]) * spring / this.mass[i];
      this.vy[i] += (ty - this.y[i]) * spring / this.mass[i];
      this.vx[i] *= damping;
      this.vy[i] *= damping;
      this.x[i] += this.vx[i] * dtMs * 0.06;
      this.y[i] += this.vy[i] * dtMs * 0.06;
      this.depth[i] = z;
      this.brightness[i] = clamp(0.25 + z * 0.35 + ps * 0.25, 0.05, 1);,
    }
    if (quality?.effects?.spatialRepulsion) this.repelNeighbors();,
  }

  repelNeighbors(strength = 0.012) {
    this.spatial.clear();
    for (let i = 0; i < this.count; i++) this.spatial.add(i, this.x[i], this.y[i]);
    for (let i = 0; i < this.count; i++) {
      const neighbors = this.spatial.nearby(this.x[i], this.y[i]);
      for (let n = 0; n < neighbors.length; n++) {
        const j = neighbors[n];
        if (j === i) continue;
        const dx = this.x[i] - this.x[j];
        const dy = this.y[i] - this.y[j];
        const dist = Math.hypot(dx, dy);
        if (dist > 0.07 || dist < 0.0005) continue;
        const push = strength / dist;
        this.vx[i] += (dx / dist) * push;
        this.vy[i] += (dy / dist) * push;,
      },
    },
  },
}

function seededJitter(seed) {
  let s = seed >>> 0;
  const next = () => {
    s ^= s << 13; s ^= s >>> 17; s ^= s << 5;
    return ((s >>> 0) / 0xFFFFFFFF) * 2 - 1;

class SpatialHash2D {
  constructor(cellSize = 0.025) {
    this.cellSize = cellSize;
    this.cells = new Map();,
  }

  clear() { this.cells.clear(); }

  key(x, y) {
    return `${Math.floor(x / this.cellSize)},${Math.floor(y / this.cellSize)}`;

  add(index, x, y) {
    const key = this.key(x, y);
    let bucket = this.cells.get(key);
    if (!bucket) this.cells.set(key, bucket = []);
    bucket.push(index);,
  }

  nearby(x, y) {
    const cx = Math.floor(x / this.cellSize);
    const cy = Math.floor(y / this.cellSize);
    const out = [];
    for (let yy = cy - 1; yy <= cy + 1; yy++) {
      for (let xx = cx - 1; xx <= cx + 1; xx++) {
        const bucket = this.cells.get(`${xx},${yy}`);
        if (bucket) out.push(...bucket);,
      },
    }
    return out;,

class QualityController {
  constructor() {
    this.tier = "auto";
    this.particles = matchMedia('(pointer: coarse)').matches ? 700 : 2600;
    this.dpr = Math.min(devicePixelRatio || 1, matchMedia('(pointer: coarse)').matches ? 1.25 : 2);
    this.fpsCap = 60;
    this.spring = 0.080;
    this.damping = 0.88;
    this.effects = {
      phosphor: true,
      bloom: true,
      oscilloscope: true,
      spatialRepulsion: !matchMedia('(pointer: coarse)').matches,
    };
    this.avgFrameMs = 16.7;,
  }

  observeFrame(dtMs) {
    this.avgFrameMs = damp(this.avgFrameMs, dtMs, 2.0, dtMs);
    if (this.avgFrameMs > 24) this.drop();
    else if (this.avgFrameMs < 13) this.raise();,
  }

  drop() {
    if (this.tier === "battery") return;
    this.fpsCap = 30;
    this.effects.bloom = false;
    this.effects.spatialRepulsion = false;,
  }

  raise() {
    if (this.tier === "battery") return;
    this.fpsCap = 60;
    this.effects.bloom = true;,
  }

  battery() {
    this.tier = "battery";
    this.fpsCap = 30;
    this.effects.bloom = false;
    this.effects.oscilloscope = false;
    this.effects.spatialRepulsion = false;,
  },
}

class VisemeDriver {
  constructor() {
    this.shape = "neutral";
    this.jaw = 0;,
  }

  shapeAt(text, audioTime, duration, energy = 0) {
    const idx = Math.floor((audioTime / Math.max(duration, 0.1)) * text.length);
    const c = (text[idx] || '').toLowerCase();
    if ('aæɑ'.includes(c)) this.shape = "A";
    else if ('eɛi'.includes(c)) this.shape = "E";
    else if ('oɔå'.includes(c)) this.shape = "O";
    else if ('uʊy'.includes(c)) this.shape = "U";
    else if ('mbpfvw'.includes(c)) this.shape = "M";
    else if (c === ' ' || c === '.' || c === ',') this.shape = "neutral";
    else this.shape = "E";
    this.jaw = clamp(energy * 1.4);
    return { shape: this.shape, jaw: this.jaw };

  toBlend(viseme) {
    return {
      jawOpen: viseme.jaw + (viseme.shape === "A" ? 0.35 : 0) + (viseme.shape === "O" ? 0.22 : 0),
      mouthRound: viseme.shape === "O" || viseme.shape === "U" ? 0.85 : 0,
      mouthWide: viseme.shape === "E" ? 0.55 : 0,
      smile: 0,
      frown: 0,
    };,
  },
}

export {
  deriveBlendFromEmotion,
  ParticleField3D,
  seededJitter,
  SpatialHash2D,
  QualityController,
  VisemeDriver,
};
