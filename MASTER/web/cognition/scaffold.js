// MASTER Cognition WebGL Scaffold - live integration
import * as THREE from 'three';

export class CognitionRenderer {
  constructor(container, scaffoldEvents){
    this.container = container;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(75, window.innerWidth/window.innerHeight, 0.1, 2000);
    this.renderer = new THREE.WebGLRenderer({alpha:true});
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    container.appendChild(this.renderer.domElement);

    this.particles = null;
    this.pressureUniforms = {
      entropy:{value:0.1}, pressure:{value:0.1}, contradiction:{value:0.0}, confidence:{value:0.8}
    };
    this.repoClusters = [];
    this.morphTargets = [];

    this.initParticles();
    this.bindEvents(scaffoldEvents);
    this.animate();
  }

  initParticles(){
    const count = 20000;
    const geometry = new THREE.BufferGeometry();
    const positions = new Float32Array(count*3);
    for(let i=0;i<count*3;i+=3){
      positions[i]=Math.random()*2-1;
      positions[i+1]=Math.random()*2-1;
      positions[i+2]=Math.random()*2-1;
    }
    geometry.setAttribute('position', new THREE.BufferAttribute(positions,3));
    const material = new THREE.PointsMaterial({size:0.02,color:0xffffff,transparent:true});
    this.particles = new THREE.Points(geometry,material);
    this.scene.add(this.particles);
  }

  bindEvents(events){
    events.bus.subscribe('pressure:updated', (payload)=>{
      this.updatePressure(payload);
    });

    events.bus.subscribe('repo_ecology:scan', (payload)=>{
      const items=[...(payload.dead_file_candidates||[]),...(payload.duplicate_basenames||[]),...(payload.large_files||[])];
      this.spawnRepoCluster(items);
    });
  }

  updatePressure(fields){
    this.pressureUniforms.entropy.value = fields.entropy;
    this.pressureUniforms.pressure.value = fields.pressure;
    this.pressureUniforms.contradiction.value = fields.contradiction;
    this.pressureUniforms.confidence.value = fields.confidence;
  }

  spawnRepoCluster(items){
    items.forEach(item=>{
      const pos=this.clusterPosition(item.path||item.basename||'unknown');
      this.repoClusters.push({x:pos.x,y:pos.y,z:pos.y*0.5});
    });
    while(this.repoClusters.length>100)this.repoClusters.shift();
  }

  clusterPosition(path,maxDepth=6){
    const parts=path.split('/');
    const depth=Math.min(parts.length-1,maxDepth);
    const x=((depth+0.5)/maxDepth)*0.8-0.4;
    const hash=this.hashString(path);
    const y=(hash%1000)/1000*0.6-0.3;
    return {x,y};
  }

  hashString(str){let h=0;for(let i=0;i<str.length;i++){h=(h<<5)-h+str.charCodeAt(i);h|=0;}return Math.abs(h);}

  addMorphTarget(geometry){this.morphTargets.push(geometry);}

  animate(){
    requestAnimationFrame(()=>this.animate());
    this.updateParticles();
    this.renderer.render(this.scene,this.camera);
  }

  updateParticles(){
    const positions=this.particles.geometry.attributes.position.array;
    for(let i=0;i<positions.length;i+=3){
      positions[i]+=(Math.random()-0.5)*0.002*this.pressureUniforms.pressure.value;
      positions[i+1]+=(Math.random()-0.5)*0.002*this.pressureUniforms.entropy.value;
      positions[i+2]+=(Math.random()-0.5)*0.002;
    }
    this.particles.geometry.attributes.position.needsUpdate=true;
  }
}