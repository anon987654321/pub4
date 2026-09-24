(() => {
"use strict";
const root=document.documentElement,canvas=document.createElement("canvas");
canvas.id="master-gravity-field";canvas.setAttribute("aria-hidden","true");
canvas.style.cssText="position:fixed;inset:0;width:100vw;height:100vh;pointer-events:none;z-index:1;opacity:.45";
document.body.appendChild(canvas);
const ctx=canvas.getContext("2d",{alpha:true}),reduced=matchMedia("(prefers-reduced-motion: reduce)").matches,points=[],count=reduced?60:180;
let w=1,h=1,activity=.12,entropy=.24,confidence=.8,ax=.5,ay=.45,last=performance.now();

function resize(){const d=Math.min(devicePixelRatio||1,1.5);w=innerWidth;h=innerHeight;canvas.width=w*d;canvas.height=h*d;ctx.setTransform(d,0,0,d,0,0)}
function seed(){points.length=0;for(let i=0;i<count;i++)points.push({x:Math.random()*w,y:Math.random()*h,vx:(Math.random()-.5)*.4,vy:(Math.random()-.5)*.4,p:Math.random()*6.28,z:.3+Math.random()*.7})}
function signal(d={}){entropy=clamp(d.entropy,entropy);confidence=clamp(d.confidence,confidence);const semantic=.18+entropy*.38+(1-confidence)*.34;activity=Math.max(activity,Math.min(1,Number(d.activity??semantic)));if(Number.isFinite(d.x))ax=d.x;if(Number.isFinite(d.y))ay=d.y;root.dataset.gravityState="active";clearTimeout(signal.t);signal.t=setTimeout(()=>{root.dataset.gravityState="quiet"},900)}

function frame(now){
  const dt=Math.min(.04,(now-last)/1000);last=now;
  activity+=(.12-activity)*dt*.8;entropy+=(.24-entropy)*dt*.8;confidence+=(.8-confidence)*dt*.7;
  ctx.clearRect(0,0,w,h);
  const tx=w*ax,ty=h*ay,accentColor=getComputedStyle(root).getPropertyValue("--c-accent")||"rgb(123 140 222)",turbulence=.8+entropy*2.2+activity*1.2;

  for(let i=0;i<points.length;i++){
    const p=points[i],dx=tx-p.x,dy=ty-p.y,dist=Math.max(60,Math.hypot(dx,dy)),pull=(.4+activity*2.2)*p.z/dist;
    p.vx+=dx*pull*dt;p.vy+=dy*pull*dt;
    const drift=Math.sin(now*.00035+p.p)*turbulence;
    p.vx+=-dy/dist*drift*dt;p.vy+=dx/dist*drift*dt;
    p.vx*=.982;p.vy*=.982;p.x+=p.vx*60*dt;p.y+=p.vy*60*dt;
    if(p.x<0)p.x=w;if(p.x>w)p.x=0;if(p.y<0)p.y=h;if(p.y>h)p.y=0;

    ctx.globalAlpha=(.08+activity*.24)*p.z;
    ctx.fillStyle=accentColor;
    const s=p.z>.7?2:1.2;
    ctx.fillRect(Math.round(p.x),Math.round(p.y),s,s);

    // Proximity constellation lines between neighboring particles
    for(let j=i+1;j<points.length;j++){
      const p2=points[j],pdx=p2.x-p.x,pdy=p2.y-p.y,pdist=Math.hypot(pdx,pdy);
      if(pdist<100){
        ctx.globalAlpha=(1-pdist/100)*.09*p.z;
        ctx.strokeStyle=accentColor;
        ctx.lineWidth=.7;
        ctx.beginPath();
        ctx.moveTo(Math.round(p.x),Math.round(p.y));
        ctx.lineTo(Math.round(p2.x),Math.round(p2.y));
        ctx.stroke();
      }
    }
  }
  ctx.globalAlpha=1;
  requestAnimationFrame(frame);
}

addEventListener("pointermove",e=>{ax=e.clientX/w;ay=e.clientY/h;root.dataset.gravityState="active";},{passive:true});
addEventListener("resize",()=>{resize();seed()},{passive:true});
addEventListener("master:visual",e=>signal(e.detail||{}));
addEventListener("gravity:signal",e=>signal(e.detail||{}));
resize();seed();if(!reduced)requestAnimationFrame(frame);
})();
function clamp(v,f){const n=Number(v);return Number.isFinite(n)?Math.max(0,Math.min(1,n)):f}
