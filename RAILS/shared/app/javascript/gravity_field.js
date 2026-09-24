const root = document.documentElement;
const field = document.createElement("div");
field.className = "gravity-field";
field.setAttribute("aria-hidden", "true");
const canvas = document.createElement("canvas");
field.append(canvas);
document.body.append(field);
const ctx = canvas.getContext("2d", { alpha: true });
const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
const points = [];
const count = reduced ? 70 : 150;
let width = 1, height = 1, activity = .08, attractX = .5, attractY = .45, last = performance.now();
function resize() { const d = Math.min(devicePixelRatio || 1, 1.5); width = innerWidth; height = innerHeight; canvas.width = Math.max(1, Math.round(width*d)); canvas.height = Math.max(1, Math.round(height*d)); ctx.setTransform(d,0,0,d,0,0); }
function seed() { points.length = 0; for (let i=0;i<count;i++) points.push({x:Math.random()*width,y:Math.random()*height,vx:0,vy:0,phase:Math.random()*Math.PI*2,depth:.25+Math.random()*.75}); }
function signal(detail={}) { activity = Math.min(1, Math.max(activity, Number(detail.activity ?? .65))); attractX = Number.isFinite(detail.x) ? detail.x : .5; attractY = Number.isFinite(detail.y) ? detail.y : .45; root.dataset.gravityState = "active"; clearTimeout(signal.timer); signal.timer = setTimeout(() => { root.dataset.gravityState = "quiet"; }, 900); }
function frame(now) { const dt=Math.min(.04,(now-last)/1000); last=now; activity += (.08-activity)*dt*(reduced?1.8:.8); ctx.clearRect(0,0,width,height); const tx=width*attractX, ty=height*attractY; const ink=getComputedStyle(root).getPropertyValue("--text") || "#fff"; for (const p of points) { const dx=tx-p.x,dy=ty-p.y,dist=Math.max(80,Math.hypot(dx,dy)),pull=(.3+activity*1.8)*p.depth/dist; p.vx+=dx*pull*dt;p.vy+=dy*pull*dt;const drift=Math.sin(now*.00035+p.phase)*(.8+activity*2);p.vx+=-dy/dist*drift*dt;p.vy+=dx/dist*drift*dt;p.vx*=.985;p.vy*=.985;p.x+=p.vx*60*dt;p.y+=p.vy*60*dt;if(p.x<-20)p.x=width+20;if(p.x>width+20)p.x=-20;if(p.y<-20)p.y=height+20;if(p.y>height+20)p.y=-20;ctx.globalAlpha=(.08+activity*.22)*p.depth;ctx.fillStyle=ink;const s=p.depth>.7?1.5:1;ctx.fillRect(Math.round(p.x),Math.round(p.y),s,s); } ctx.globalAlpha=1; if(!reduced) requestAnimationFrame(frame); }
addEventListener("resize",()=>{resize();seed();},{passive:true});
document.addEventListener("pointermove",e=>{attractX=e.clientX/Math.max(1,width);attractY=e.clientY/Math.max(1,height);},{passive:true});
addEventListener("master:visual",e=>signal(e.detail||{}));
addEventListener("gravity:signal",e=>signal(e.detail||{}));
document.addEventListener("turbo:load", () => signal({ activity: .34 }), { passive: true });
document.addEventListener("turbo:frame-load", () => signal({ activity: .28 }), { passive: true });
document.addEventListener("click", e => { if (e.target.closest("a,button,[role=button]")) signal({ activity: .42, x: e.clientX / Math.max(1,width), y: e.clientY / Math.max(1,height) }); }, { passive: true });
document.addEventListener("input", () => signal({ activity: .26 }), { passive: true });
resize();seed();if(reduced) field.hidden=true;else requestAnimationFrame(frame);
