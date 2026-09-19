const VERT_SHADER = `
vec3 mod289v3(vec3 x){return x-floor(x*(1./289.))*289.;}
vec4 mod289v4(vec4 x){return x-floor(x*(1./289.))*289.;}
vec4 permute4(vec4 x){return mod289v4(((x*34.)+1.)*x);}
vec4 taylorInvSqrt4(vec4 r){return 1.79284291400159-0.85373472095314*r;}
float snoise(vec3 v){
  const vec2 C=vec2(1./6.,1./3.);const vec4 D=vec4(0.,.5,1.,2.);
  vec3 i=floor(v+dot(v,C.yyy));vec3 x0=v-i+dot(i,C.xxx);
  vec3 g=step(x0.yzx,x0.xyz);vec3 l=1.-g;
  vec3 i1=min(g.xyz,l.zxy);vec3 i2=max(g.xyz,l.zxy);
  vec3 x1=x0-i1+C.xxx;vec3 x2=x0-i2+C.yyy;vec3 x3=x0-D.yyy;
  i=mod289v3(i);
  vec4 p=permute4(permute4(permute4(i.z+vec4(0.,i1.z,i2.z,1.))+i.y+vec4(0.,i1.y,i2.y,1.))+i.x+vec4(0.,i1.x,i2.x,1.));
  float n_=.142857142857;vec3 ns=n_*D.wyz-D.xzx;
  vec4 j=p-49.*floor(p*ns.z*ns.z);
  vec4 x_=floor(j*ns.z);vec4 y_=floor(j-7.*x_);
  vec4 x=x_*ns.x+ns.yyyy;vec4 y=y_*ns.x+ns.yyyy;vec4 h=1.-abs(x)-abs(y);
  vec4 b0=vec4(x.xy,y.xy);vec4 b1=vec4(x.zw,y.zw);
  vec4 s0=floor(b0)*2.+1.;vec4 s1=floor(b1)*2.+1.;vec4 sh=-step(h,vec4(0.));
  vec4 a0=b0.xzyw+s0.xzyw*sh.xxyy;vec4 a1=b1.xzyw+s1.xzyw*sh.zzww;
  vec3 p0=vec3(a0.xy,h.x);vec3 p1=vec3(a0.zw,h.y);vec3 p2=vec3(a1.xy,h.z);vec3 p3=vec3(a1.zw,h.w);
  vec4 norm=taylorInvSqrt4(vec4(dot(p0,p0),dot(p1,p1),dot(p2,p2),dot(p3,p3)));
  p0*=norm.x;p1*=norm.y;p2*=norm.z;p3*=norm.w;
  vec4 m=max(.6-vec4(dot(x0,x0),dot(x1,x1),dot(x2,x2),dot(x3,x3)),0.);m=m*m;
  return 42.*dot(m*m,vec4(dot(p0,x0),dot(p1,x1),dot(p2,x2),dot(p3,x3)));
}
vec3 curlNoise(vec3 p){
  const float e=.07;
  float n1,n2,n3,n4;
  n1=snoise(p+vec3(0,e,0));n2=snoise(p-vec3(0,e,0));
  n3=snoise(p+vec3(0,0,e));n4=snoise(p-vec3(0,0,e));
  float cx=(n1-n2)/(2.*e)-(n3-n4)/(2.*e);
  vec3 q=p+vec3(31.416);
  n1=snoise(q+vec3(0,0,e));n2=snoise(q-vec3(0,0,e));
  n3=snoise(q+vec3(e,0,0));n4=snoise(q-vec3(e,0,0));
  float cy=(n1-n2)/(2.*e)-(n3-n4)/(2.*e);
  vec3 r=p+vec3(17.);
  n1=snoise(r+vec3(e,0,0));n2=snoise(r-vec3(e,0,0));
  n3=snoise(r+vec3(0,e,0));n4=snoise(r-vec3(0,e,0));
  float cz=(n1-n2)/(2.*e)-(n3-n4)/(2.*e);
  return vec3(cx,cy,cz);
}
uniform float uMorph;
uniform float uTime;
uniform vec3 uColor;
uniform float uHc;
uniform float uCurl;
uniform float uJaw;
uniform vec2 uMouse;
uniform float uBass;
uniform float uMids;
uniform float uHighs;
uniform float uConfidence;
uniform float uTremor;
uniform float uTilt;
uniform float uRain;
uniform float uModelSwitch;
uniform float uEarPulse;
uniform float uRipple;
uniform float uVowel;
uniform float uSurpriseY;
uniform float uFracture;
uniform float uBloom;
uniform float uIdleDrift;
uniform float uEyeClose;
uniform float uExposure;
uniform float uQuestion;
attribute vec3 scatter;
attribute vec3 position_target;
attribute float seed;
attribute float curvature;
attribute float boundary;
attribute float zone;
varying float vAlpha;
varying vec3 vColor;
varying float vDepth;
varying float vZoneVal;
void main(){
  float m=smoothstep(0.,1.,uMorph);
  vec2 cursorFace=uMouse*0.44;
  float cursorProx=1.0-smoothstep(0.0,0.22,length(position.xy-cursorFace));
  float lm=max(m,cursorProx*0.96);
  float curiousPull = uTilt * cursorProx * 0.045;
  float curlAmp=uCurl*0.28*(1.0-uRain*0.18);
  vec3 noise=curlNoise(position*0.5+uTime*0.1+seed)*(1.-m)*curlAmp;
  float jawRgn=smoothstep(0.0,0.15,-position.y-0.12)*smoothstep(0.0,0.14,0.28-abs(position.x));
  
  // Phenotype Morphing: blend between original position and target Homo Futura position
  vec3 morphedPos = mix(position, position_target, m);
  
  vec3 p=mix(scatter,morphedPos,lm)+noise+vec3(0.,-uJaw*0.05*jawRgn,0.);
  p.xy += normalize(cursorFace - p.xy + vec2(0.001)) * curiousPull;
  float tremorf=snoise(position*18.0+uTime*3.2+seed)*uTremor*0.003;
  p+=vec3(tremorf,tremorf*0.7,0.0);
  vec2 diff2d=p.xy-uMouse;
  float dist2d=length(diff2d);
  if(dist2d<0.20&&dist2d>0.001)p.xy+=normalize(diff2d)*(0.20-dist2d)*0.32;
  float radial=length(p.xy);
  p.z+=sin(radial*11.0-uTime*3.8)*uBass*0.05*lm;
  p.y -= uRain * (0.5 + position.y * 0.5) * sin(seed * 6.28 + uTime * 1.8) * 0.07;
  float isEar = 1.0 - smoothstep(0.0, 0.08, abs(zone - 0.2));
  p.xy += normalize(p.xy + vec2(0.001)) * isEar * uEarPulse * sin(uTime * 9.0 + seed) * 0.022;
  p.xy *= 1.0 + (1.0 - uConfidence) * 0.045;
  if(uRipple > 0.0) {
    float rwave = sin(radial * 10.0 - uRipple * 18.0) * exp(-uRipple * 2.5) * 0.035;
    p.xy += normalize(p.xy + vec2(0.001)) * rwave;
  }
  float jawRgnV = smoothstep(0.0,0.15,-position.y-0.05) * smoothstep(0.0,0.18,0.30-abs(position.x));
  p.y -= uVowel * jawRgnV * 0.025;
  p.y += uSurpriseY * smoothstep(0.0, 0.6, 0.5 + position.y * 0.8) * 0.12;
  if(uFracture > 0.0) {
    float ang = atan(position.y, position.x);
    float shardAng = floor(ang * 4.0 / 3.14159 + 0.5) * 3.14159 / 4.0;
    p.xy += vec2(cos(shardAng), sin(shardAng)) * uFracture * (0.22 + seed * 0.32);
  }
  if(uModelSwitch > 0.0) {
    float dissolve = smoothstep(0.0, 0.45, uModelSwitch) * (1.0 - smoothstep(0.55, 1.0, uModelSwitch));
    p += curlNoise(position * 0.9 + seed + vec3(uTime * 0.2)) * dissolve * 0.045;
  }
  if(uQuestion > 0.0) {
    float qt = clamp(uQuestion, 0.0, 1.0);
    float qSeed = fract(seed * 13.37 + uTime * 0.12);
    vec2 qStem = vec2(0.02 * sin(qSeed * 18.0), 0.10 - qSeed * 0.34);
    vec2 qHook = vec2(0.11 * cos(qSeed * 6.2831), 0.12 + 0.10 * sin(qSeed * 6.2831));
    vec2 qTarget = qSeed < 0.62 ? qHook : qStem;
    p.xy = mix(p.xy, qTarget, qt * 0.88);
    p.z += qt * 0.02 * sin(seed * 6.2831);
  }
  if(uBloom > 0.0) p.xy += normalize(p.xy + vec2(0.001)) * uBloom * 0.30 * (1.0 - radial * 0.6);
  vec4 mv=modelViewMatrix*vec4(p,1.);
  float depth=clamp(p.z/0.82,0.,1.);
  gl_PointSize=1.0;
  gl_Position=projectionMatrix*mv;
  float form=0.78+curvature*0.62+depth*1.22+boundary*0.42;
  float hc=uHc;
  float zoneAudio=0.0;
  if(zone<0.1) zoneAudio=uBass*0.18;
  else if(zone<0.3) zoneAudio=uMids*0.12;
  else if(zone<0.5) zoneAudio=uBass*0.08;
  else if(zone<0.7) zoneAudio=uHighs*0.14;
  else zoneAudio=uMids*0.10;
  float eyeRgn = smoothstep(0.30,0.50,zone) * (1.0 - smoothstep(0.50,0.65,zone));
  float eyeDim = 1.0 - uEyeClose * eyeRgn * 0.82;
  vAlpha=(hc>0.0?hc:mix(0.28+uIdleDrift*0.08,0.48+depth*0.52,lm)+zoneAudio)*eyeDim;
  float flickerFreq=0.5+seed*1.5;
  float flicker=1.0+0.08*sin(seed*6.2831+uTime*flickerFreq);
  vAlpha*=flicker*uExposure;
  vAlpha*=1.0-0.45*clamp(uModelSwitch,0.0,1.0);
  vAlpha*=1.0-0.35*clamp(uQuestion,0.0,1.0);
  vAlpha*=clamp(form*0.42,0.25,1.0);
  vAlpha=max(vAlpha,0.08);
  float shade=mix(0.35,1.0,depth)*2.2;
  vec3 warmDepth=mix(vec3(0.74,0.66,0.58),vec3(1.0,0.98,0.94),depth);
  vColor=(hc>0.0?vec3(1.0,1.0,1.0):uColor*warmDepth*shade);
  vDepth=depth;
  vZoneVal=zone;
}
`;

const FRAG_SHADER = `
varying float vAlpha;
varying vec3 vColor;
varying float vDepth;
varying float vZoneVal;
uniform float uFocusDim;
void main(){
  float alpha=vAlpha*uFocusDim;
  float eyeRgn=smoothstep(0.30,0.50,vZoneVal)*(1.0-smoothstep(0.50,0.65,vZoneVal));
  float mouthRgn=smoothstep(0.68,0.82,vZoneVal);
  float zoneDim=mix(1.0,mix(0.82,0.96,mouthRgn),eyeRgn*0.48);
  alpha*=zoneDim;
  gl_FragColor=vec4(clamp(vColor,0.0,1.0),max(0.0,alpha));
}
`;

export { VERT_SHADER, FRAG_SHADER };
