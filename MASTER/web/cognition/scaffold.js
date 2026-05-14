// MASTER Cognition WebGL Scaffold
// Purpose: GPU particle swarm, semantic terrain, pressure-field uniforms
// Volumetric cognition-space renderer, Three.js setup

import * as THREE from 'three';

export class CognitionRenderer {
  constructor(container) {
    this.container = container;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 2000);
    this.renderer = new THREE.WebGLRenderer({ alpha: true });
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    container.appendChild(this.renderer.domElement);

    this.particles = null; // will hold GPU-instanced particles
    this.pressureUniforms = {
      entropy: { value: 0.1 },
      pressure: { value: 0.1 },
      contradiction: { value: 0.0 },
      confidence: { value: 0.8 }
    };

    this.initParticles();
    this.animate();
  }

  initParticles() {
    const particleCount = 10000;
    const geometry = new THREE.BufferGeometry();
    const positions = new Float32Array(particleCount * 3);
    for(let i=0;i<particleCount*3;i+=3){
      positions[i] = Math.random()*2-1;
      positions[i+1] = Math.random()*2-1;
      positions[i+2] = Math.random()*2-1;
    }
    geometry.setAttribute('position', new THREE.BufferAttribute(positions,3));

    const material = new THREE.PointsMaterial({ size: 0.02, color: 0xffffff, transparent: true });
    this.particles = new THREE.Points(geometry, material);
    this.scene.add(this.particles);
  }

  animate() {
    requestAnimationFrame(()=>this.animate());
    this.updateParticles();
    this.renderer.render(this.scene, this.camera);
  }

  updateParticles() {
    const positions = this.particles.geometry.attributes.position.array;
    for(let i=0;i<positions.length;i+=3){
      positions[i] += (Math.random()-0.5)*0.002;
      positions[i+1] += (Math.random()-0.5)*0.002;
      positions[i+2] += (Math.random()-0.5)*0.002;
    }
    this.particles.geometry.attributes.position.needsUpdate = true;
  }

  updatePressure(fields){
    this.pressureUniforms.entropy.value = fields.entropy;
    this.pressureUniforms.pressure.value = fields.pressure;
    this.pressureUniforms.confidence.value = fields.confidence;
    this.pressureUniforms.contradiction.value = fields.contradiction;
  }
}