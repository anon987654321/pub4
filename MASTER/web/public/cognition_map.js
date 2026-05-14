(() => {
  "use strict";

  const canvas = document.getElementById("cognition-map") || makeCanvas();
  const ctx = canvas.getContext("2d", { alpha: true });
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const state = { w:1, h:1, dpr: Math.min(devicePixelRatio||1,2), entropy:0.16, confidence:0.86, pressure:0.18, zoom:1, layer:"cognition", time:0 };

  const nodes=[], edges=[], flows=[], vectors=[], agents=[
    mkAgent("planner", -0.34, -0.18, "230,180,110"),
    mkAgent("retriever", 0.27, -0.22, "120,190,230"),
    mkAgent("judge", 0.35, 0.14, "230,120,95"),
    mkAgent("memory", -0.22, 0.24, "145,235,190"),
    mkAgent("executor", 0.02, 0.34, "220,180,240")
  ];

  const repoMarkers=[];

  function mkAgent(name,x,y,color){return{name,x,y,tx:x,ty:y,color,charge:0.35,phase:Math.random()*6.28}};
  function makeCanvas(){const n=document.createElement("canvas");n.id="cognition-map";n.setAttribute("aria-hidden","true");document.body.prepend(n);return n;}

  function resize(){state.w=innerWidth;state.h=innerHeight;canvas.width=Math.floor(state.w*state.dpr);canvas.height=Math.floor(state.h*state.dpr);canvas.style.cssText="position:fixed;inset:0;width:100vw;height:100vh;z-index:-2;pointer-events:none;mix-blend-mode:screen;opacity:.72";ctx.setTransform(state.dpr,0,0,state.dpr,0,0);seedGraph();seedVectors();}

  // PressureEngine integration
  function updatePressure(){
    if(window.MASTERPressure){
      const pFields=window.MASTERPressure.getFields();
      state.entropy=pFields.entropy;
      state.confidence=pFields.confidence;
      state.pressure=window.MASTERPressure.getPressure();
    }
  }

  function ingest(detail={}){updatePressure();const name=String(detail.name||detail.mode||"event");state.layer=layerFor(name);pulseNodes(name);pulseAgents(name);spawnFlow(name,detail);}

  window.addEventListener("pressure:update",(e)=>{const f=e.detail;state.entropy=f.entropy;state.confidence=f.confidence;state.pressure=f.pressure;});

  window.addEventListener("repo_ecology:scan",(e)=>{
    const data=e.detail.visual||{};
    state.entropy=data.entropy??state.entropy;
    state.confidence=data.confidence??state.confidence;
    state.pressure=data.pressure??state.pressure;

    (e.detail.dead_file_candidates||[]).forEach(item=>spawnRepoMarker(item,"dead"));
    (e.detail.duplicate_basenames||[]).forEach(item=>spawnRepoMarker(item,"duplicate"));
    (e.detail.large_files||[]).forEach(item=>spawnRepoMarker(item,"large"));
  });

  function clusterPosition(path,maxDepth=6){
    const parts=path.split('/');
    const depth=Math.min(parts.length-1,maxDepth);
    const x=((depth+0.5)/maxDepth)*0.8-0.4;
    const hash=hashString(path);
    const y=(hash%1000)/1000*0.6-0.3;
    return {x,y};
  }

  function hashString(str){let h=0;for(let i=0;i<str.length;i++){h=(h<<5)-h+str.charCodeAt(i);h|=0;}return Math.abs(h);}

  function spawnRepoMarker(item,kind){
    const pos=clusterPosition(item.path||item.basename||"unknown");
    const radius=rand(0.008,0.018);
    let color;
    switch(kind){case"dead":color="235,80,45";break;case"duplicate":color="230,185,110";break;case"large":color="130,230,190";break;default:color="190,210,230";break;}
    repoMarkers.push({x:pos.x,y:pos.y,radius,color,life:1,kind});
    while(repoMarkers.length>60)repoMarkers.shift();
  }

  function layerFor(name){if(/repo|ecology|reference|scan|sweep/.test(name))return"repo";if(/memory|retriev|context/.test(name))return"memory";if(/error|rollback|failed|escalat|fallback/.test(name))return"pressure";if(/epistemic|contradiction|confidence|scrutiny/.test(name))return"epistemic";return"cognition";}
  function pulseNodes(name){nodes.forEach(node=>{node.heat=name.includes(node.name)||state.layer.includes(node.name)?1:Math.max(node.heat,0.35)});}
  function pulseAgents(name){agents.forEach(a=>{if(name.includes(a.name))a.charge=1;else if(/memory|retriev/.test(name)&&a.name==="memory")a.charge=1;else if(/error|rollback|epistemic|contradiction/.test(name)&&a.name==="judge")a.charge=1;else a.charge=Math.max(a.charge,0.45);a.tx=a.x+rand(-0.05,0.05)*state.pressure;a.ty=a.y+rand(-0.04,0.04)*state.pressure;});}
  function spawnFlow(name,detail){const color=colorFor(name,detail);const count=reduced?1:3;for(let i=0;i<count;i++){const a=rand(0,Math.PI*2);flows.push({x:Math.cos(a)*rand(0.08,0.38),y:Math.sin(a)*rand(0.06,0.28),vx:Math.cos(a+Math.PI/2)*rand(0.001,0.004),vy:Math.sin(a+Math.PI/2)*rand(0.001,0.004),life:1,color})}while(flows.length>(reduced?24:96))flows.shift();}
  function colorFor(name,detail={}){const p=String(detail.provider||"").toLowerCase();if(p.includes("claude"))return"230,120,80";if(p.includes("deepseek"))return"100,170,230";if(/error|rollback|escalat|fallback|contradiction/.test(name))return"235,80,45";if(/memory|retriev/.test(name))return"130,230,190";if(/repo|ecology|reference/.test(name))return"230,185,110";return"190,210,230";}
  function project(x,y,lift=0){const s=Math.min(state.w,state.h)*0.78*state.zoom;return{x:state.w*0.5+x*s,y:state.h*0.52+y*s*0.72-lift*s*0.05}};

  function drawRepoMarkers(){for(let i=repoMarkers.length-1;i>=0;i--){const m=repoMarkers[i];m.life-=0.002;if(m.life<=0){repoMarkers.splice(i,1);continue;}const p=project(m.x,m.y,m.life*0.18);ctx.beginPath();ctx.strokeStyle=`rgba(${m.color},${m.life*0.16})`;ctx.lineWidth=1;ctx.arc(p.x,p.y,m.radius*Math.min(state.w,state.h)*(1.5-m.life*0.4),0,Math.PI*2);ctx.stroke();}}

  function frame(now){state.time=now;updatePressure();const t=now*0.00035;ctx.clearRect(0,0,state.w,state.h);ctx.globalCompositeOperation="lighter";drawTerrain(t);drawGraph();drawVectors(t);drawFlows();drawAgents(t);drawRepoMarkers();requestAnimationFrame(frame);}

  addEventListener("resize",resize,{passive:true});
  addEventListener("master:visual",(event)=>ingest(event.detail||{}));
  window.MASTERMap={state,nodes,edges,agents,event:(name,detail={})=>ingest({...detail,name})};

  resize();requestAnimationFrame(frame);
})();