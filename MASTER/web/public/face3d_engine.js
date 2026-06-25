import { ZONES, ZONE_NAMES, buildCanonicalMask, maskAnchors2D, DEFAULT_BLEND, DEFAULT_EMOTION } from '/face3d_geometry.js';
import { deriveBlendFromEmotion, ParticleField3D, SpatialHash2D, QualityController, VisemeDriver } from '/face3d_support.js';

class Face3DEngine {
  constructor({ count } = {}) {
    this.quality = new QualityController();
    this.topology = buildCanonicalMask("sepik");
    this.particles = new ParticleField3D(count || this.quality.particles);
    this.particles.assignStable(this.topology);
    this.blend = { ...DEFAULT_BLEND };
    this.emotion = { ...DEFAULT_EMOTION };
    this.pose = { yaw: 0, pitch: 0, roll: 0 };
    this.visemes = new VisemeDriver();
  }

  setMask(kind) {
    this.topology = buildCanonicalMask(kind);
    this.particles.assignStable(this.topology);
  }

  setEmotion(patch) {
    this.emotion = { ...this.emotion, ...patch };
    this.blend = deriveBlendFromEmotion(this.emotion, this.blend);
  }

  setBlend(patch) {
    this.blend = { ...this.blend, ...patch };
  }

  setPose(patch) {
    this.pose = { ...this.pose, ...patch };
  }

  speakFrame(text, audioTime, duration, energy = 0) {
    const viseme = this.visemes.shapeAt(text, audioTime, duration, energy);
    this.setBlend(this.visemes.toBlend(viseme));
    return viseme;
  }

  tick(dtMs) {
    this.quality.observeFrame(dtMs);
    this.particles.updateHomes(this.topology, this.blend);
    this.particles.tick(dtMs, this.pose, this.quality);
  }

  snapshot() {
    return {
      count: this.particles.count,
      x: this.particles.x,
      y: this.particles.y,
      depth: this.particles.depth,
      brightness: this.particles.brightness,
      zone: this.particles.zone
    };
  }
}

window.MasterFace3D = Object.freeze({
  ZONES,
  ZONE_NAMES,
  buildCanonicalMask,
  maskAnchors2D,
  applyBlendshape,
  deriveBlendFromEmotion,
  ParticleField3D,
  SpatialHash2D,
  QualityController,
  VisemeDriver,
  Face3DEngine
});

export {
  ZONES,
  ZONE_NAMES,
  buildCanonicalMask,
  maskAnchors2D,
  applyBlendshape,
  deriveBlendFromEmotion,
  ParticleField3D,
  SpatialHash2D,
  QualityController,
  VisemeDriver,
  Face3DEngine
};
