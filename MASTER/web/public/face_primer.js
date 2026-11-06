// The primer and boot path of the chat face, loaded by chat/index.html.erb as
// a synchronous classic script right after #primer, so its handlers are wired
// before any other script runs. A digested file rather than inline: cached
// across visits, linted and tested like the rest of public/.
//
// Deferred-boot contract: go() is the only way into the face. It sets
// window._primerFired, imports face.js (the URL the view hands over in
// data-face-module) and watches for a painted frame; #prompt-form and
// #ui-status are resolved lazily in go(), not at parse time.
(function(){
  // document.currentScript is only set while this file first runs.
  const FACE_MODULE=document.currentScript?.dataset.faceModule||'/face.js';
  const p=document.getElementById('primer');
  let fired=false,timer=null,fallback=null,hintT=null,retryT=null,started=false,failedShown=false;
  function promptFormEl(){return document.getElementById('prompt-form');}
  function uiEl(){return document.getElementById('ui-status');}
  function titleEl(){return document.getElementById('primer-title');}
  function i18n(key, fallback, vars){
    const raw=p?.getAttribute('data-i18n-'+key)||fallback;
    if(!vars)return raw;
    return raw.replace(/%\{(\w+)\}/g,function(_,name){return vars[name]});
  }
  function primeAudio(){
    try{
      const Ctx=window.AudioContext||window.webkitAudioContext;
      if(!Ctx||window.__MASTER_AUDIO_PRIME__)return;
      let ctx=new Ctx();
      window.__MASTER_AUDIO_PRIME__=ctx;
      ctx.resume().catch(function(){});
    }catch(_e){}
  }
  function dismissPrimer(){
    document.body.classList.remove('face-loading');
    if(!p)return;
    p.classList.add('gone');
    window.setTimeout(function(){p.remove();},220);
  }
  function revealPrompt(){
    const z=promptFormEl(),ui=uiEl();
    if(z)z.classList.add('live');
    if(ui&&!ui.textContent)ui.textContent=i18n('starting','starting…');
    // Keyboard users: land focus in the prompt after primer dismiss.
    const zin=document.getElementById('prompt-input');
    if(zin){try{zin.focus({preventScroll:true});}catch(_e){try{zin.focus();}catch(__e){}}}
  }
  function boot(){
    if(started)return true;
    if(window.MASTER_FACE&&window.MASTER_FACE.startEverything){
      started=true;
      window.MASTER_FACE.startEverything();
      return true;
    }
    return false;
  }
  function clearWatch(){
    clearTimeout(hintT);clearTimeout(retryT);clearTimeout(fallback);
    clearInterval(timer);timer=null;
    if(typeof window.stop2DFallback==='function')window.stop2DFallback();
    let ui=uiEl();
    if(ui?.dataset.bootLoading){ui.textContent='';delete ui.dataset.bootLoading;}
  }
  function bootFailed(){
    clearWatch();
    window.MASTER?.boot?.transition?.('ERROR', { source: 'bootFailed' });
    fallbackUi();
  }
  // Indeterminate on purpose: nothing here can measure how far the face
  // import has got, and a counter that climbs on a timer says it can.
  function showLoadState(){
    let title=titleEl(),ui=uiEl();
    if(title)title.textContent=i18n('loading-title','loading…');
    if(ui){ui.dataset.bootLoading='1';ui.textContent=i18n('loading-status','loading the face…');}
  }
  function fallbackUi(){
    dismissPrimer();
    revealPrompt();
    let ui=uiEl();
    if(ui)ui.textContent=i18n('failed','face failed to load — reload or check console');
    let errLive=document.getElementById('error-live');
    if(errLive){
      errLive.textContent=i18n('failed-live',
        'face failed to load (WebGL/primer timing?). Reload or see browser console for MASTER_FACE errors.');
    }
    failedShown=true;
  }
  // A face that paints after the watchdog gave up has disproved the
  // announcement, and a screen reader must not keep the false one.
  addEventListener('master:face-ready',function(){
    if(!failedShown)return;
    failedShown=false;
    let ui=uiEl(),errLive=document.getElementById('error-live');
    if(ui)ui.textContent='';
    if(errLive)errLive.textContent='';
  });
  function resetFaceCanvasForWebGL(){
    const cv=document.getElementById('face');
    if(!cv||!cv.parentNode)return;
    const fresh=cv.cloneNode(false);
    cv.parentNode.replaceChild(fresh,cv);
  }
  function loadFace(retried){
    if(window.__MASTER_FACE_IMPORT__)return;
    window.__MASTER_FACE_IMPORT__=true;
    if(retried)window.MASTER?.boot?.transition?.('RECOVERING', { source: 'loadFace_retry' });
    window.MASTER?.boot?.transition?.('ASSETS', { source: 'loadFace', retried: !!retried });
    resetFaceCanvasForWebGL();
    import(FACE_MODULE).then(function(){
      if(boot())clearWatch();
    }).catch(function(){
      window.__MASTER_FACE_IMPORT__=false;
      if(retried){bootFailed();return;}
      let ui=uiEl();
      if(ui)ui.textContent=i18n('retrying','retrying…');
      window.MASTER?.boot?.transition?.('RECOVERING', { source: 'loadFace_catch' });
      retryT=setTimeout(function(){loadFace(true);},1200);
    });
  }
  function go(){
    if(fired)return;
    fired=true;
    window.MASTER?.boot?.transition?.('PRIMER', { source: 'primer_tap' });
    const title=titleEl();
    if(title)title.textContent=i18n('starting','starting…');
    window._primerFired=true;
    window.dispatchEvent(new CustomEvent('primer:ready'));
    primeAudio();
    dismissPrimer();
    revealPrompt();
    if(typeof window.start2DFallback==='function')window.start2DFallback();
    loadFace();
    if(boot())return;
    showLoadState();
    hintT=setTimeout(function(){
      const ui=uiEl();
      if(ui)ui.textContent=i18n('still-loading','still loading the face…');
    },8000);
    timer=setInterval(function(){
      if(boot())clearWatch();
    },40);
    fallback=setTimeout(function(){
      const f=window.MASTER_FACE;
      // primerFired only proves startEverything() ran, not that anything
      // painted - a WebGLRenderer that threw during construction (caught
      // and swallowed downstream) leaves primerFired true and the canvas
      // permanently black. dbgFrames only increments from inside a real
      // frame() call, so it's the actual evidence of rendering.
      const painted=f?.primerFired&&!window.__MASTER_RENDERER_FAILED__&&(f.dbgFrames>0||!f.renderer);
      if(painted){clearWatch();}else{bootFailed();}
    },35000);
  }
  window.__MASTER_PRIMER_GO__=go;
  window.__MASTER_PRIMER_TAP__=go;
  if(p){
    ['pointerdown','click','touchend'].forEach(function(ev){
      p.addEventListener(ev,go,{capture:true,passive:true});
    });
  }
  addEventListener('keydown',function(e){
    if(!fired&&(e.key==='Enter'||e.key===' ')){e.preventDefault();go();}
  });
  // Autostart is the default: no "launch AI" screen between the visitor and
  // the face. Embeds and ?autostart=1 already took this path, so this flips
  // which case is the exception rather than adding a new boot route — the
  // one below has been the exercised path for every front-page embed.
  // ?primer=1 keeps the old overlay for debugging the gesture path itself.
  //
  // What the tap did that a page load cannot: supply the user gesture an
  // AudioContext needs. primeAudio() now runs against a page that has had no
  // interaction, so the context is created 'suspended' and ctx.resume()
  // rejects. The listeners below resume it on the first real interaction —
  // any pointerdown or keydown, including the one that sends the first
  // prompt — so speech works from the first reply without a screen whose
  // only job was to collect a click.
  try{
    const q=new URLSearchParams(location.search||'');
    if(q.get('portrait')==='1') document.body.dataset.portrait='1';
    if(q.get('film')==='1') document.body.dataset.film='1';
    if(q.get('primer')!=='1'&&document.body.dataset.primer!=='keep'){
      document.body.classList.add('primer-autostart');
      if(p){p.setAttribute('aria-hidden','true');p.tabIndex=-1;}
      setTimeout(go,0);

      const resumeAudio=function(){
        const ctx=window.__MASTER_AUDIO_PRIME__;
        if(ctx?.state==='suspended'){try{ctx.resume();}catch(_e){}}
        if(!ctx){primeAudio();return;}
        if(ctx.state==='running'){
          ['pointerdown','keydown','touchend'].forEach(function(ev){
            removeEventListener(ev,resumeAudio,{capture:true});
          });
        }
      };
      ['pointerdown','keydown','touchend'].forEach(function(ev){
        addEventListener(ev,resumeAudio,{capture:true,passive:true});
      });
    }
  }catch(_e){}
})();
