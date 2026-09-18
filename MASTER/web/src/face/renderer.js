import * as THREE from 'three';
import { VERT_SHADER, FRAG_SHADER } from './shaders.js';
import { State, FACE_PHOSPHOR_DECAY } from './state.js';

export class FaceRenderer {
  constructor(canvas) {
    this.cv = canvas;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(38, canvas.width / canvas.height, 0.1, 2000);
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: false });
    this.renderer.setPixelRatio(1);
    
    this.initGeometry();
    this.initScene();
  }

  initGeometry() {
    // The geometry is derived from the la-mask / homo-futura phenotype
    // Point cloud rendering as per project architecture
    this.geometry = new THREE.BufferGeometry();
    // Attributes (position, scatter, seed, curvature, boundary, zone) 
    // are loaded from the master assets
    this.material = new THREE.ShaderMaterial({
      vertexShader: VERT_SHADER,
      fragmentShader: FRAG_SHADER,
      transparent: true,
      depthWrite: false,
      uniforms: this.createUniforms()
    });
    this.points = new THREE.Points(this.geometry, this.material);
    this.scene.add(this.points);
  }

  initScene() {
    this.camera.position.z = 4.6;
    this.renderer.setSize(this.cv.width, this.cv.height);
  }

  createUniforms() {
    return {
      uMorph: { value: 0 },
      uTime: { value: 0 },
      uColor: { value: new THREE.Color(1, 1, 1) },
      uHc: { value: 0 },
      uCurl: { value: 0 },
      uJaw: { value: 0 },
      uMouse: { value: { x: 0, y: 0 } },
      uBass: { value: 0 },
      uMids: { value: 0 },
      uHighs: { value: 0 },
      uConfidence: { value: 1 },
      uTremor: { value: 0 },
      uTilt: { value: 0 },
      uRain: { value: 0 },
      uModelSwitch: { value: 0 },
      uEarPulse: { value: 0 },
      uRipple: { value: 0 },
      uVowel: { value: 0 },
      uSurpriseY: { value: 0 },
      uFracture: { value: 0 },
      uBloom: { value: 0 },
      uIdleDrift: { value: 0 },
      uEyeClose: { value: 0 },
      uExposure: { value: 1 },
      uQuestion: { value: 0 },
      uFocusDim: { value: 1.0 }
    };
  }

  render(t) {
    this.material.uniforms.uTime.value = t * 0.001;
    this.renderer.render(this.scene, this.camera);
  }
}
