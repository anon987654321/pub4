// The seven 2D renderers radio cycles through after the tunnel, one step per
// track: infinity grid, cymatic waves, fractal cascade, vortex nest, neural web,
// cosmic emanation, hypergrid spiral. Their bodies, colours and timings are the
// original source. The three globals they read are module names here, because
// the page that set those globals is not the page they run on.
//
// They write pixels into an ImageData buffer. The tunnel canvas already carries
// a WebGL context and a canvas holds one context, so they draw on a second
// canvas laid over it. radio_brgen_tunnel.js imports this module the first time
// a track changes, which is why its pin does not preload.

// THEMES[0], the palette the renderers were written against. Nothing on the
// radio switches theme.
const vizTheme=0;

const NO_PARALLAX={x:0,y:0};

const motionScale=()=>typeof matchMedia==="function"&&matchMedia("(prefers-reduced-motion: reduce)").matches?.35:1;

const pack32=(r,g,b,a)=>((a&255)<<24)|((b&255)<<16)|((g&255)<<8)|(r&255);

const TAU=Math.PI*2,THIRD_PI=Math.PI/3,PHI=1.618033988749895;

const makeRotation=(cx,cy,angle)=>{const c=Math.cos(angle),s=Math.sin(angle);return{x:(x,y)=>cx+(x-cx)*c-(y-cy)*s,y:(x,y)=>cy+(x-cx)*s+(y-cy)*c};};

const atmosphericHue=(depth,baseHue)=>baseHue+(1-depth)*30;

const SimplexNoise=(function(){const F2=0.5*(Math.sqrt(3)-1),G2=(3-Math.sqrt(3))/6,F3=1/3,G3=1/6;const grad3=[[1,1,0],[-1,1,0],[1,-1,0],[-1,-1,0],[1,0,1],[-1,0,1],[1,0,-1],[-1,0,-1],[0,1,1],[0,-1,1],[0,1,-1],[0,-1,-1]];function Noise(r){let p,perm,permMod12;r===undefined&&(r=Math.random);p=new Uint8Array(256);for(let i=0;i<256;i++)p[i]=i;for(let i=255;i>0;i--){const n=Math.floor((i+1)*r()),q=p[i];p[i]=p[n];p[n]=q}perm=new Uint8Array(512);permMod12=new Uint8Array(512);for(let i=0;i<512;i++){perm[i]=p[i&255];permMod12[i]=perm[i]%12}this.perm=perm;this.permMod12=permMod12}Noise.prototype.noise2D=function(xin,yin){const perm=this.perm,permMod12=this.permMod12;let n0,n1,n2;const s=(xin+yin)*F2,i=Math.floor(xin+s),j=Math.floor(yin+s),t=(i+j)*G2,X0=i-t,Y0=j-t,x0=xin-X0,y0=yin-Y0;let i1,j1;if(x0>y0){i1=1;j1=0}else{i1=0;j1=1}const x1=x0-i1+G2,y1=y0-j1+G2,x2=x0-1+2*G2,y2=y0-1+2*G2;const ii=i&255,jj=j&255;let t0=0.5-x0*x0-y0*y0;if(t0<0)n0=0;else{const gi=permMod12[ii+perm[jj]];t0*=t0;n0=t0*t0*(grad3[gi][0]*x0+grad3[gi][1]*y0)}let t1=0.5-x1*x1-y1*y1;if(t1<0)n1=0;else{const gi=permMod12[ii+i1+perm[jj+j1]];t1*=t1;n1=t1*t1*(grad3[gi][0]*x1+grad3[gi][1]*y1)}let t2=0.5-x2*x2-y2*y2;if(t2<0)n2=0;else{const gi=permMod12[ii+1+perm[jj+1]];t2*=t2;n2=t2*t2*(grad3[gi][0]*x2+grad3[gi][1]*y2)}return 70*(n0+n1+n2)};return Noise})();

const noise=new SimplexNoise();

const THEMES=[
  {name:'Original',fn:(i,l,a)=>{const b=Math.max(0,Math.min(1,a?.bass??.5)),v=Math.max(0,Math.min(1,a?.average??.45)),h=Math.max(0,Math.min(1,a?.high??.35)),d=i/Math.max(1,l-1),r=Math.round(20+60*d),g=Math.round(40+120*v),u=Math.round(180*b+75*h);return pack32(r,g,u,255);}},
  {name:'Synthwave',fn:(i,l,a)=>{const v=Math.max(0,Math.min(1,a?.average??.5)),d=i/Math.max(1,l-1);const r=Math.round(255*Math.pow(d,2)+80*v),g=Math.round(30+120*v),b=Math.round(255*d);return pack32(r,g,b,255);}},
  {name:'Neon',fn:(i,l,a)=>{const h=Math.max(0,Math.min(1,a?.high??.5)),m=Math.max(0,Math.min(1,a?.mid??.5)),d=i/Math.max(1,l-1);const r=Math.round(50+205*h),g=Math.round(255*m),b=Math.round(50+205*d);return pack32(r,g,b,255);}},
  {name:'Fire',fn:(i,l,a)=>{const v=Math.max(0,Math.min(1,a?.average??.5)),b=Math.max(0,Math.min(1,a?.bass??.5)),d=i/Math.max(1,l-1);const r=255,g=Math.round(100*d+155*v),u=Math.round(30*b);return pack32(r,g,u,255);}},
  {name:'Ocean',fn:(i,l,a)=>{const m=Math.max(0,Math.min(1,a?.mid??.5)),h=Math.max(0,Math.min(1,a?.high??.5)),d=i/Math.max(1,l-1);const r=Math.round(30*d),g=Math.round(100+155*m),b=Math.round(150+105*h);return pack32(r,g,b,255);}},
  {name:'Mono',fn:(i,l,a)=>{const v=Math.max(0,Math.min(1,a?.average??.5)),d=i/Math.max(1,l-1);const c=Math.round(100+155*(v*0.5+d*0.5));return pack32(c,c,c,255);}}
];

const drawLine=(u32,w,h,x1,y1,x2,y2,col)=>{let dx=Math.abs(x2-x1),dy=Math.abs(y2-y1),sx=x1<x2?1:-1,sy=y1<y2?1:-1,err=dx-dy;for(;;){if(x1>=0&&x1<w&&y1>=0&&y1<h)u32[x1+y1*w]=col;if(x1===x2&&y1===y2)break;const e2=2*err;if(e2>-dy){err-=dy;x1+=sx;}if(e2<dx){err+=dx;y1+=sy;}}};

const drawCircle=(u32,w,h,cx,cy,radius,col,gradient)=>{const r2=radius*radius;for(let dx=-radius;dx<=radius;dx++){for(let dy=-radius;dy<=radius;dy++){const dist=dx*dx+dy*dy;if(dist<=r2){const px=(cx+dx)|0,py=(cy+dy)|0;if(px>=0&&px<w&&py>=0&&py<h){if(gradient){const bright=1-Math.sqrt(dist)/(radius*1.5);const alpha=(col>>>24)&255,blue=(col>>>16)&255,green=(col>>>8)&255,red=col&255;const r2=(red*bright)|0,g2=(green*bright)|0,b2=(blue*bright)|0;u32[px+py*w]=pack32(r2,g2,b2,alpha)}else{u32[px+py*w]=col}}}}}};

const initBuffer=(ctx,w,h)=>{const imageData=ctx.getImageData(0,0,w,h);const u32=new Uint32Array(imageData.data.buffer);const t=new Uint8ClampedArray(4);t[3]=255;const BLACK32=new Uint32Array(t.buffer)[0];return{imageData,u32,BLACK32}};

// VIZ 1: INFINITY GRID - Dense square tunnel grid with beat pops & rotation
class InfinityGridViz{constructor(ctx){this.ctx=ctx;this.w=0;this.h=0;this.time=0;this.grids=[];this.rotation=0;this.beatPop=0;}resize(w,h,s){this.w=w;this.h=h;this.imageData=this.ctx.getImageData(0,0,w,h);this.u32=new Uint32Array(this.imageData.data.buffer);const t=new Uint8ClampedArray(4);t[3]=255;this.BLACK32=new Uint32Array(t.buffer)[0];this.grids=[];for(let i=0;i<120;i++){this.grids.push({z:-250+i*4,ox:Math.random()*60-30,oy:Math.random()*60-30});}}frame(a){try{this.u32.fill(this.BLACK32);const p=NO_PARALLAX;const cx=this.w/2+p.x,cy=this.h/2+p.y,m=motionScale();this.time+=m*0.5;this.rotation+=m*0.01;this.beatPop=this.beatPop*0.85+(a?.beat||0)*0.15;const audioExpand=(a?.average||0)*60+this.beatPop*40;const speed=1.5+m*0.5;const rot=makeRotation(cx,cy,this.rotation);for(let i=0;i<this.grids.length;i++){const g=this.grids[i];g.z+=speed;if(g.z>250){g.z-=500;g.ox=Math.random()*60-30;g.oy=Math.random()*60-30;}const sc=300/(300+g.z),size=(80+audioExpand)*sc;const offX=g.ox*(1-g.z/250),offY=g.oy*(1-g.z/250);const gridCX=cx+offX*sc,gridCY=cy+offY*sc;const depth=Math.max(0,1-g.z/250);const hue=atmosphericHue(depth,this.time*20)%360/360;const col=THEMES[vizTheme].fn(hue*255,255,a);const x1=(gridCX-size)|0,y1=(gridCY-size)|0,x2=(gridCX+size)|0,y2=(gridCY+size)|0;const rx1=rot.x(x1,y1)|0,ry1=rot.y(x1,y1)|0,rx2=rot.x(x2,y1)|0,ry2=rot.y(x2,y1)|0;const rx3=rot.x(x2,y2)|0,ry3=rot.y(x2,y2)|0,rx4=rot.x(x1,y2)|0,ry4=rot.y(x1,y2)|0;drawLine(this.u32,this.w,this.h,rx1,ry1,rx2,ry2,col);drawLine(this.u32,this.w,this.h,rx2,ry2,rx3,ry3,col);drawLine(this.u32,this.w,this.h,rx3,ry3,rx4,ry4,col);drawLine(this.u32,this.w,this.h,rx4,ry4,rx1,ry1,col);const mid=(size*0.5)|0;if(mid>2){const mx1=(gridCX-mid)|0,my1=(gridCY-mid)|0,mx2=(gridCX+mid)|0,my2=(gridCY+mid)|0;const rmx1=rot.x(mx1,my1)|0,rmy1=rot.y(mx1,my1)|0,rmx2=rot.x(mx2,my1)|0,rmy2=rot.y(mx2,my1)|0;const rmx3=rot.x(mx2,my2)|0,rmy3=rot.y(mx2,my2)|0,rmx4=rot.x(mx1,my2)|0,rmy4=rot.y(mx1,my2)|0;drawLine(this.u32,this.w,this.h,rmx1,rmy1,rmx2,rmy2,col);drawLine(this.u32,this.w,this.h,rmx2,rmy2,rmx3,rmy3,col);drawLine(this.u32,this.w,this.h,rmx3,rmy3,rmx4,rmy4,col);drawLine(this.u32,this.w,this.h,rmx4,rmy4,rmx1,rmy1,col);}if(i%2===0&&i<this.grids.length-1){const g2=this.grids[i+1],sc2=300/(300+g2.z),size2=(80+audioExpand)*sc2;const offX2=g2.ox*(1-g2.z/250),offY2=g2.oy*(1-g2.z/250);const gCX2=cx+offX2*sc2,gCY2=cy+offY2*sc2;const c1x=rot.x(gridCX-size,gridCY-size)|0,c1y=rot.y(gridCX-size,gridCY-size)|0;const c2x=rot.x(gCX2-size2,gCY2-size2)|0,c2y=rot.y(gCX2-size2,gCY2-size2)|0;drawLine(this.u32,this.w,this.h,c1x,c1y,c2x,c2y,col);}}this.ctx.putImageData(this.imageData,0,0);}catch(e){console.error('InfinityGridViz:',e);}}}

// VIZ 2: CYMATIC WAVES - 6-way symmetric mandala with wave interference
class CymaticWavesViz{constructor(ctx){this.ctx=ctx;this.w=0;this.h=0;this.time=0;this.waves=[];this.layers=[];}resize(w,h,s){this.w=w;this.h=h;this.imageData=this.ctx.getImageData(0,0,w,h);this.u32=new Uint32Array(this.imageData.data.buffer);const t=new Uint8ClampedArray(4);t[3]=255;this.BLACK32=new Uint32Array(t.buffer)[0];this.waves=[];this.layers=[];for(let i=0;i<100;i++){this.waves.push({z:-300+i*6,segs:24,freq:1+Math.random()*0.5});}for(let i=0;i<3;i++){this.layers.push({phase:Math.random()*TAU,speed:0.3+i*0.2});}}frame(a){try{this.u32.fill(this.BLACK32);const p=NO_PARALLAX;const cx=this.w/2+p.x,cy=this.h/2+p.y,m=motionScale();this.time+=m*0.6;const audioRipple=(a?.average||0)*80+(a?.beat||0)*40;const speed=1.8;for(const w of this.waves){w.z+=speed;if(w.z>300){w.z-=600;w.freq=1+Math.random()*0.5;}const sc=350/(350+w.z);const baseRad=60+audioRipple+noise.noise2D(w.z*0.01,this.time*0.1)*25;const interference=Math.sin(w.z*0.05*w.freq+this.time*w.freq)*0.3;const rad=(baseRad+baseRad*interference)*sc;const depth=Math.max(0,1-w.z/300);const hue=atmosphericHue(depth,depth*180)%360/360;const col=THEMES[vizTheme].fn(hue*255,255,a);for(let sym=0;sym<6;sym++){const symAng=sym*THIRD_PI;for(let i=0;i<w.segs;i++){const ang1=(i/w.segs)*TAU+this.time*0.3+symAng,ang2=((i+1)/w.segs)*TAU+this.time*0.3+symAng;const wobble=noise.noise2D(Math.cos(ang1)*3,Math.sin(ang1)*3+this.time*0.2)*15*sc;const x1=(cx+Math.cos(ang1)*(rad+wobble))|0,y1=(cy+Math.sin(ang1)*(rad+wobble))|0;const wobble2=noise.noise2D(Math.cos(ang2)*3,Math.sin(ang2)*3+this.time*0.2)*15*sc;const x2=(cx+Math.cos(ang2)*(rad+wobble2))|0,y2=(cy+Math.sin(ang2)*(rad+wobble2))|0;drawLine(this.u32,this.w,this.h,x1,y1,x2,y2,col);}}}for(let i=0;i<this.layers.length;i++){const l=this.layers[i];l.phase+=m*l.speed*0.05;const lrad=(40+i*25+audioRipple*0.5)*((Math.sin(l.phase)+1.5)/2.5);const lcol=THEMES[vizTheme].fn(128+i*40,255,a);for(let sym=0;sym<6;sym++){const ang=sym*THIRD_PI+l.phase;const lx=(cx+Math.cos(ang)*lrad)|0,ly=(cy+Math.sin(ang)*lrad)|0;drawCircle(this.u32,this.w,this.h,lx,ly,3+i,lcol,false);}}this.ctx.putImageData(this.imageData,0,0);}catch(e){console.error('CymaticWavesViz:',e);}}}

// VIZ 3: FRACTAL CASCADE - 4-way symmetric fractal with pulsing zoom
class FractalCascadeViz{constructor(ctx){this.ctx=ctx;this.w=0;this.h=0;this.time=0;this.branches=[];this.zoom=1;}resize(w,h,s){this.w=w;this.h=h;this.imageData=this.ctx.getImageData(0,0,w,h);this.u32=new Uint32Array(this.imageData.data.buffer);const t=new Uint8ClampedArray(4);t[3]=255;this.BLACK32=new Uint32Array(t.buffer)[0];this.branches=[];for(let i=0;i<40;i++){this.branches.push({z:-200+i*10,ang:Math.random()*Math.PI*2});}}frame(a){try{this.u32.fill(this.BLACK32);const p=NO_PARALLAX;const cx=this.w/2+p.x,cy=this.h/2+p.y,m=motionScale();this.time+=m*0.7;this.zoom=1+Math.sin(this.time*0.3)*0.15*(a?.average||0);const audioGrow=(a?.bass||0)*60+(a?.beat||0)*30;for(const b of this.branches){b.z+=2;if(b.z>200){b.z-=400;b.ang=Math.random()*Math.PI*2;}const sc=280/(280+b.z)*this.zoom,len=(40+audioGrow)*sc;const depth=Math.max(0,1-b.z/200);const hue=((depth*200+this.time*30)%360)/360;const col=THEMES[vizTheme].fn(hue*255,255,a);for(let sym=0;sym<4;sym++){const symAng=sym*Math.PI/2;const branches=3;for(let i=0;i<branches;i++){const ang=b.ang+this.time*0.2+(i/branches)*Math.PI*2+symAng;const x2=cx+Math.cos(ang)*len,y2=cy+Math.sin(ang)*len;drawLine(this.u32,this.w,this.h,cx,cy,x2|0,y2|0,col);const subAng1=ang-0.6,subAng2=ang+0.6;const sx1=x2+Math.cos(subAng1)*len*0.35,sy1=y2+Math.sin(subAng1)*len*0.35;const sx2=x2+Math.cos(subAng2)*len*0.35,sy2=y2+Math.sin(subAng2)*len*0.35;drawLine(this.u32,this.w,this.h,x2|0,y2|0,sx1|0,sy1|0,col);drawLine(this.u32,this.w,this.h,x2|0,y2|0,sx2|0,sy2|0,col);}}}this.ctx.putImageData(this.imageData,0,0);}catch(e){console.error('FractalCascadeViz:',e);}}}

// VIZ 4: VORTEX NEST - Golden ratio spirals with atmospheric depth
class VortexNestViz{constructor(ctx){this.ctx=ctx;this.w=0;this.h=0;this.time=0;this.spirals=[];}resize(w,h,s){this.w=w;this.h=h;this.imageData=this.ctx.getImageData(0,0,w,h);this.u32=new Uint32Array(this.imageData.data.buffer);const t=new Uint8ClampedArray(4);t[3]=255;this.BLACK32=new Uint32Array(t.buffer)[0];this.spirals=[];for(let i=0;i<50;i++){this.spirals.push({z:-250+i*10,arms:3,rot:Math.random()*TAU});}}frame(a){try{this.u32.fill(this.BLACK32);const p=NO_PARALLAX;const cx=this.w/2+p.x,cy=this.h/2+p.y,m=motionScale();this.time+=m*0.5;const audioTwist=(a?.average||0)*2+(a?.beat||0);for(const sp of this.spirals){sp.z+=2;sp.rot+=0.03*m;if(sp.z>250){sp.z-=500;sp.rot=Math.random()*TAU;}const sc=300/(300+sp.z);const depth=Math.max(0,1-sp.z/250);const hue=atmosphericHue(depth,depth*240)%360/360;const col=THEMES[vizTheme].fn(hue*255,255,a);for(let arm=0;arm<sp.arms;arm++){const baseAng=sp.rot+(arm/sp.arms)*TAU;for(let i=0;i<10;i++){const t=i/10,t2=(i+1)/10;const spiral1=t*PHI*TAU+this.time*0.5+sp.z*0.01+audioTwist,spiral2=t2*PHI*TAU+this.time*0.5+sp.z*0.01+audioTwist;const rad1=(20+t*80)*sc,rad2=(20+t2*80)*sc;const ang1=baseAng+spiral1,ang2=baseAng+spiral2;const x1=(cx+Math.cos(ang1)*rad1)|0,y1=(cy+Math.sin(ang1)*rad1)|0;const x2=(cx+Math.cos(ang2)*rad2)|0,y2=(cy+Math.sin(ang2)*rad2)|0;drawLine(this.u32,this.w,this.h,x1,y1,x2,y2,col);}}}this.ctx.putImageData(this.imageData,0,0);}catch(e){console.error('VortexNestViz:',e);}}}

// VIZ 5: NEURAL WEB - Interconnected neural network nodes pulsing
class NeuralWebViz{constructor(ctx){this.ctx=ctx;this.w=0;this.h=0;this.time=0;this.neurons=[];}resize(w,h,s){const buf=initBuffer(this.ctx,w,h);this.w=w;this.h=h;this.imageData=buf.imageData;this.u32=buf.u32;this.BLACK32=buf.BLACK32;this.neurons=[];for(let i=0;i<60;i++){this.neurons.push({z:-200+i*7,x:(Math.random()-0.5)*200,y:(Math.random()-0.5)*200,connections:[]});}}frame(a){try{this.u32.fill(this.BLACK32);const p=NO_PARALLAX;const cx=this.w/2+p.x,cy=this.h/2+p.y,m=motionScale();this.time+=m*0.6;const audioPulse=(a?.beat||0)*30;for(const n of this.neurons){n.z+=1.3;if(n.z>200){n.z-=400;n.x=(Math.random()-0.5)*200;n.y=(Math.random()-0.5)*200;}const sc=320/(320+n.z);const nx=(cx+n.x*sc)|0,ny=(cy+n.y*sc)|0;const pulse=(5+audioPulse)*sc;const depth=Math.max(0,1-n.z/200);const col=THEMES[vizTheme].fn(depth*255,255,a);drawCircle(this.u32,this.w,this.h,nx,ny,pulse,col,false);for(const n2 of this.neurons){if(n2===n||n2.z<n.z)continue;const dist=Math.hypot(n.x-n2.x,n.y-n2.y);if(dist<180){const sc2=320/(320+n2.z);const n2x=(cx+n2.x*sc2)|0,n2y=(cy+n2.y*sc2)|0;const strength=1-dist/180;if(Math.random()<strength*0.3){drawLine(this.u32,this.w,this.h,nx,ny,n2x,n2y,col);}}}}this.ctx.putImageData(this.imageData,0,0);}catch(e){console.error('NeuralWebViz:',e);}}}

// VIZ 6: COSMIC EMANATION - Divine rays from central sun with orbital spheres (Fludd-inspired)
class CosmicEmanationViz{constructor(ctx){this.ctx=ctx;this.w=0;this.h=0;this.time=0;this.rays=[];this.spheres=[];}resize(w,h,s){const buf=initBuffer(this.ctx,w,h);this.w=w;this.h=h;this.imageData=buf.imageData;this.u32=buf.u32;this.BLACK32=buf.BLACK32;this.rays=[];this.spheres=[];const rayCount=64;for(let i=0;i<rayCount;i++){this.rays.push({angle:i/rayCount*Math.PI*2,z:-150+Math.random()*300});}for(let i=0;i<12;i++){this.spheres.push({orbit:80+i*25,angle:Math.random()*Math.PI*2,speed:0.3+Math.random()*0.4,size:8-i*0.5,z:-100+i*15});}}frame(a){try{this.u32.fill(this.BLACK32);const p=NO_PARALLAX;const cx=this.w/2+p.x,cy=this.h/2+p.y,m=motionScale();this.time+=m*0.4;const bassExtend=(a?.bass||0)*120+(a?.beat||0)*60;const midSwirl=(a?.average||0)*0.5;const highFlicker=(a?.high||0)*15;for(const r of this.rays){r.z+=0.8;if(r.z>150)r.z-=300;const sc=220/(220+r.z);const rayLen=(100+bassExtend)*sc;const wobble=noise.noise2D(r.angle*3,this.time*0.2)*0.15;const ang=r.angle+wobble+midSwirl;const x2=(cx+Math.cos(ang)*rayLen)|0,y2=(cy+Math.sin(ang)*rayLen)|0;const depth=Math.max(0,1-Math.abs(r.z)/150);const col=THEMES[vizTheme].fn(depth*255,255,a);drawLine(this.u32,this.w,this.h,cx,cy,x2,y2,col);}const sunSize=(25+bassExtend*0.2)|0;const sunCol=THEMES[vizTheme].fn(255,255,a);drawCircle(this.u32,this.w,this.h,cx,cy,sunSize,sunCol,false);for(const s of this.spheres){s.angle+=s.speed*m*0.02+midSwirl*0.3;s.z+=0.5;if(s.z>100)s.z-=200;const sc=250/(250+s.z);const orbitRad=(s.orbit+highFlicker)*sc;const sx=(cx+Math.cos(s.angle)*orbitRad)|0,sy=(cy+Math.sin(s.angle)*orbitRad)|0;const sphSize=(s.size+highFlicker*0.3)*sc;const depth=Math.max(0,1-Math.abs(s.z)/100);const col=THEMES[vizTheme].fn(depth*255,255,a);drawCircle(this.u32,this.w,this.h,sx,sy,sphSize,col,false);}this.ctx.putImageData(this.imageData,0,0);}catch(e){console.error('CosmicEmanationViz:',e);}}}

// VIZ 7: HYPERGRID SPIRAL - Hybrid with particle trails
class HypergridSpiralViz{constructor(ctx){this.ctx=ctx;this.w=0;this.h=0;this.time=0;this.grids=[];this.particles=[];this.rotation=0;}resize(w,h,s){const buf=initBuffer(this.ctx,w,h);this.w=w;this.h=h;this.imageData=buf.imageData;this.u32=buf.u32;this.BLACK32=buf.BLACK32;this.grids=[];this.particles=[];for(let i=0;i<80;i++){this.grids.push({z:-200+i*5,rot:0});}for(let i=0;i<120;i++){this.particles.push({angle:Math.random()*TAU,radius:Math.random()*150,z:-200+Math.random()*400,speed:0.5+Math.random()*1.5,orbitSpeed:0.02+Math.random()*0.04,trail:[]});}}frame(a){try{for(let i=0;i<this.u32.length;i++){const r=(this.u32[i]&255),g=(this.u32[i]>>8&255),b=(this.u32[i]>>16&255);this.u32[i]=pack32((r*0.92)|0,(g*0.92)|0,(b*0.92)|0,255);}const p=NO_PARALLAX;const cx=this.w/2+p.x,cy=this.h/2+p.y,m=motionScale();this.time+=m*0.6;this.rotation+=m*0.015;const beatPulse=(a?.beat||0)*50;const audioExpand=(a?.average||0)*40;const rot=makeRotation(cx,cy,this.rotation);for(const g of this.grids){g.z+=1.2*m;g.rot+=0.02*m;if(g.z>200){g.z-=400;}const sc=250/(250+g.z);const size=(50+audioExpand+beatPulse)*sc;const depth=Math.max(0,1-Math.abs(g.z)/200);const hue=atmosphericHue(depth,this.time*25)%360/360;const col=THEMES[vizTheme].fn(hue*255,255,a);const grot=makeRotation(cx,cy,this.rotation+g.rot);const x1=(cx-size)|0,y1=(cy-size)|0,x2=(cx+size)|0,y2=(cy+size)|0;const rx1=grot.x(x1,y1)|0,ry1=grot.y(x1,y1)|0,rx2=grot.x(x2,y1)|0,ry2=grot.y(x2,y1)|0;const rx3=grot.x(x2,y2)|0,ry3=grot.y(x2,y2)|0,rx4=grot.x(x1,y2)|0,ry4=grot.y(x1,y2)|0;drawLine(this.u32,this.w,this.h,rx1,ry1,rx2,ry2,col);drawLine(this.u32,this.w,this.h,rx2,ry2,rx3,ry3,col);drawLine(this.u32,this.w,this.h,rx3,ry3,rx4,ry4,col);drawLine(this.u32,this.w,this.h,rx4,ry4,rx1,ry1,col);}for(const pt of this.particles){pt.z+=pt.speed*m;pt.angle+=pt.orbitSpeed*m;if(pt.z>200){pt.z-=400;pt.radius=Math.random()*150;pt.angle=Math.random()*TAU;pt.trail=[];}const sc=280/(280+pt.z);const spiral=pt.z*0.03+this.time*0.5;const r=(pt.radius+Math.sin(spiral)*20)*sc;const ang=pt.angle+spiral;const px=(cx+Math.cos(ang)*r)|0,py=(cy+Math.sin(ang)*r)|0;const depth=Math.max(0,1-Math.abs(pt.z)/200);const hue2=atmosphericHue(depth,this.time*40)%360/360;const pcol=THEMES[vizTheme].fn(hue2*255,255,a);const psize=(2+beatPulse*0.08)*sc;drawCircle(this.u32,this.w,this.h,px,py,Math.max(1,psize|0),pcol,false);}this.ctx.putImageData(this.imageData,0,0);}catch(e){console.error('HypergridSpiralViz:',e);}}}

// Index 0 is the tunnel, which renders itself on its own canvas.
const RENDERERS=[null,InfinityGridViz,CymaticWavesViz,FractalCascadeViz,VortexNestViz,NeuralWebViz,CosmicEmanationViz,HypergridSpiralViz];

export class VisualizerDeck {
  constructor(tunnelCanvas) {
    this.canvas = document.createElement("canvas")
    this.canvas.setAttribute("aria-hidden", "true")
    this.canvas.style.imageRendering = "pixelated"
    // style.display rather than the hidden attribute: `.radio-tunnel canvas`
    // sets display:block, which outranks the [hidden] rule.
    this.canvas.style.display = "none"
    tunnelCanvas.after(this.canvas)
    this.ctx = this.canvas.getContext("2d", { alpha: false, willReadFrequently: true }) || this.canvas.getContext("2d")
    this.renderers = []
  }

  get size() { return RENDERERS.length }

  show(mode, width, height) {
    if (!RENDERERS[mode]) {
      this.canvas.style.display = "none"
      return
    }
    this.renderers[mode] ??= new RENDERERS[mode](this.ctx)
    this.resize(mode, width, height)
    this.canvas.style.display = ""
  }

  resize(mode, width, height) {
    const renderer = this.renderers[mode]
    if (!renderer) return
    if (this.canvas.width !== width || this.canvas.height !== height) {
      this.canvas.width = width
      this.canvas.height = height
    }
    renderer.resize(width, height, 1)
  }

  frame(mode, audioData) { this.renderers[mode]?.frame(audioData) }

  destroy() { this.canvas.remove() }
}
