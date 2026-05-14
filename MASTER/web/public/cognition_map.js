(() => {
  "use strict";

  const canvas = document.getElementById("cognition-map") || makeCanvas();
  const ctx = canvas.getContext("2d", { alpha: true });
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const state = { w:1, h:1, dpr: Math.min(devicePixelRatio||1,2), entropy:0.16, confidence:0.86, pressure:0.18, zoom:1, layer:"cognition", time:0 };

  const nodes=[], edges=[], flows=[], vectors=[], repoMarkers=[], agents=[
    mkAgent("planner", -0.34, -0.18, "230,180,110"),
    mkAgent("retriever", 0.27, -0.22, "120,190,230"),
    mkAgent("judge", 0.35, 0.14, "230,120,95"),
    mkAgent("memory", -0.22, 0.24, "145,235,190"),
    mkAgent("executor", 0.02, 0.34, "220,180,240")
  ];

  function mkAgent(name,x,y,color){return{name,x,y,tx:x,ty:y,color,charge:0.35,phase:Math.random()*6.28}};
  function makeCanvas(){const n=document.createElement("canvas");n.id="cognition-map";n.setAttribute("aria-hidden","true");document.body.prepend(n);return n;}

  function resize(){state.w=innerWidth;state.h=innerHeight;canvas.width=Math.floor(state.w*state.dpr);canvas.height=Math.floor(state.h*state.dpr);canvas.style.cssText="position:fixed;inset:0;width:100vw;height:100vh;z-index:-2;pointer-events:none;mix-blend-mode:screen;opacity:.72";ctx.setTransform(state.dpr,0,0,state.dpr,0,0);seedGraph();seedVectors();}

  function seedGraph(){
    nodes.length=0;edges.length=0;
    const names=["agent","memory","repo","governance","epistemics","tools","visual","pipeline","cache"];
    names.forEach((name,i)=>{const a=(i/names.length)*Math.PI*2;nodes.push({name,x:Math.cos(a)*0.36,y:Math.sin(a)*0.25,heat:0.18});});
    [["agent","pipeline"],["pipeline","tools"],["pipeline","governance"],["agent","memory"],["memory","epistemics"],["repo","tools"],["repo","visual"],["cache","agent"],["epistemics","governance"]].forEach(([from,to])=>edges.push({from,to,pulse:Math.random()}));
  }

  function seedVectors(){
    vectors.length=0;const cols=reduced?7:13;const rows=reduced?5:9;
    for(let y=0;y<rows;y++){for(let x=0;x<cols;x++){const nx=x/(cols-1)-0.5;const ny=y/(rows-1)-0.5;vectors.push({x:nx,y:ny,a:Math.atan2(ny,nx)+Math.PI/2,force:0.1});}}
  }

  function updatePressure(){
    if(window.MASTERPressure){
      const pFields=window.MASTERPressure.getFields();
      state.entropy=pFields.entropy;
      state.confidence=pFields.confidence;
      state.pressure=window.MASTERPressure.getPressure();
    }
  }

  function ingest(detail={}){updatePressure();const name=String(detail.name||detail.mode||"event");state.layer=layerFor(name);pulseNodes(name);pulseAgents(name);spawnFlow(name,detail);}

  window.addEventListener("pressure:update",(e)=>{const f=e.detail||{};state.entropy=f.entropy??state.entropy;state.confidence=f.confidence??state.confidence;state.pressure=f.pressure??state.pressure;});

  window.addEventListener("repo_ecology:scan",(e)=>{
    const data=e.detail?.visual||{};
    state.entropy=data.entropy??state.entropy;
    state.confidence=data.confidence??state.confidence;
    state.pressure=data.pressure??state.pressure;
    (e.detail?.dead_file_candidates||[]).forEach(item=>spawnRepoMarker(item,"dead"));
    (e.detail?.duplicate_basenames||[]).forEach(item=>spawnRepoMarker(item,"duplicate"));
    (e.detail?.large_files||[]).forEach(item=>spawnRepoMarker(item,"large"));
  });

  function clusterPosition(path,maxDepth=6){const parts=String(path).split('/');const depth=Math.min(parts.length-1,maxDepth);const x=((depth+0.5)/maxDepth)*0.8-0.4;const hash=hashString(path);const y=(hash%1000)/1000*0.6-0.3;return {x,y};}
  function hashString(str){let h=0;String(str).split('').forEach(ch=>{h=(h<<5)-h+ch.charCodeAt(0);h|=0;});return Math.abs(h);}

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

  function drawTerrain(t){
    const rows=reduced?10:18;const cols=reduced?16:30;
    for(let r=0;r<rows;r++){ctx.beginPath();for(let c=0;c<cols;c++){const x=c/(cols-1)-0.5;const y=r/(rows-1)-0.5;const h=noise(x*5,y*5,t)*(0.35+state.entropy);const p=project(x,y,h);if(c===0)ctx.moveTo(p.x,p.y);else ctx.lineTo(p.x,p.y);}const color=state.layer==="pressure"?"235,80,45":"110,210,180";ctx.strokeStyle=`rgba(${color},${0.035+state.pressure*0.045})`;ctx.lineWidth=0.7+state.entropy*0.8;ctx.stroke();}
  }

  function drawGraph(){
    const byName=new Map(nodes.map(node=>[node.name,node]));
    edges.forEach(edge=>{const a=byName.get(edge.from);const b=byName.get(edge.to);if(!a||!b)return;edge.pulse=(edge.pulse+0.006+state.pressure*0.008)%1;const pa=project(a.x,a.y,a.heat*0.1);const pb=project(b.x,b.y,b.heat*0.1);ctx.beginPath();ctx.strokeStyle=`rgba(145,210,230,${0.035+(a.heat+b.heat)*0.025})`;ctx.lineWidth=0.8;ctx.moveTo(pa.x,pa.y);ctx.lineTo(pb.x,pb.y);ctx.stroke();ctx.beginPath();ctx.fillStyle="rgba(245,220,160,.22)";ctx.arc(pa.x+(pb.x-pa.x)*edge.pulse,pa.y+(pb.y-pa.y)*edge.pulse,2.2,0,Math.PI*2);ctx.fill();});
    nodes.forEach(node=>{node.heat+=(0.16-node.heat)*0.01;const p=project(node.x,node.y,node.heat*0.16);ctx.beginPath();ctx.fillStyle=`rgba(230,185,110,${0.08+node.heat*0.16})`;ctx.arc(p.x,p.y,4+node.heat*7,0,Math.PI*2);ctx.fill();});
  }

  function drawVectors(t){vectors.forEach(v=>{v.a+=Math.sin(t+v.x*5+v.y*3)*0.002+state.pressure*0.003;v.force+=(state.pressure-v.force)*0.01;const p=project(v.x,v.y);const len=8+v.force*18;ctx.beginPath();ctx.strokeStyle=`rgba(235,95,65,${0.025+v.force*0.09})`;ctx.lineWidth=0.7;ctx.moveTo(p.x,p.y);ctx.lineTo(p.x+Math.cos(v.a)*len,p.y+Math.sin(v.a)*len);ctx.stroke();});}

  function drawFlows(){for(let i=flows.length-1;i>=0;i--){const f=flows[i];f.life-=0.004;f.x+=f.vx*(1+state.pressure*3);f.y+=f.vy*(1+state.pressure*3);if(f.life<=0){flows.splice(i,1);continue;}const p=project(f.x,f.y,f.life*0.12);ctx.beginPath();ctx.fillStyle=`rgba(${f.color},${f.life*0.22})`;ctx.arc(p.x,p.y,2+f.life*3,0,Math.PI*2);ctx.fill();}}

  function drawAgents(t){agents.forEach(a=>{a.phase+=0.012+a.charge*0.01;a.charge+=(0.32-a.charge)*0.012;a.x+=(a.tx-a.x)*0.018;a.y+=(a.ty-a.y)*0.018;const p=project(a.x,a.y,a.charge*0.18+Math.sin(a.phase+t)*0.05);ctx.beginPath();ctx.fillStyle=`rgba(${a.color},${0.11+a.charge*0.30})`;ctx.arc(p.x,p.y,5+a.charge*9,0,Math.PI*2);ctx.fill();ctx.beginPath();ctx.strokeStyle=`rgba(${a.color},${0.07+a.charge*0.16})`;ctx.arc(p.x,p.y,14+a.charge*20,0,Math.PI*2);ctx.stroke();});}

  function drawRepoMarkers(){for(let i=repoMarkers.length-1;i>=0;i--){const m=repoMarkers[i];m.life-=0.002;if(m.life<=0){repoMarkers.splice(i,1);continue;}const p=project(m.x,m.y,m.life*0.18);ctx.beginPath();ctx.strokeStyle=`rgba(${m.color},${m.life*0.16})`;ctx.lineWidth=1;ctx.arc(p.x,p.y,m.radius*Math.min(state.w,state.h)*(1.5-m.life*0.4),0,Math.PI*2);ctx.stroke();}}

  function frame(now){state.time=now;updatePressure();const t=now*0.00035;ctx.clearRect(0,0,state.w,state.h);ctx.globalCompositeOperation="lighter";drawTerrain(t);drawGraph();drawVectors(t);drawFlows();drawAgents(t);drawRepoMarkers();requestAnimationFrame(frame);}
  function noise(x,y,t){return Math.sin(x*1.8+t)*0.42+Math.cos(y*2.1-t*0.7)*0.34+Math.sin((x+y)*1.2+t*1.3)*0.24;}
  function rand(min,max){return min+Math.random()*(max-min);}

  addEventListener("resize",resize,{passive:true});
  addEventListener("master:visual",(event)=>ingest(event.detail||{}));
  window.MASTERMap={state,nodes,edges,agents,repoMarkers,event:(name,detail={})=>ingest({...detail,name})};

  resize();requestAnimationFrame(frame);
})();