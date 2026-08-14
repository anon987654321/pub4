const F_FACE_LOOPS = window.MASTER_FACE || {};
const F_FACE_TTS = F_FACE_LOOPS.tts || window.tts;

window._endlessWhite = (() => {
  let ctx, m, playing = false, iv = null;
  const CHORDS = [
    [220.00, 261.63, 329.63, 392.00, 493.88],
    [293.66, 349.23, 440.00, 523.25, 659.25],
    [349.23, 440.00, 523.25, 659.25, 783.99],
    [329.63, 392.00, 493.88, 587.33, 698.46]
  ];
  const BPM = 75, BEAT = 60 / BPM;
  function impulse(d=2.6, k=2.4) {
    const sr = ctx.sampleRate, n = sr * d, buf = ctx.createBuffer(2, n, sr);
    for (let c = 0; c < 2; c++) { const x = buf.getChannelData(c); for (let i = 0; i < n; i++) x[i] = (Math.random()*2-1) * Math.pow(1-i/n, k); }
    return buf;
  }
  function noise(d=1.0) {
    const sr = ctx.sampleRate, n = sr * d, buf = ctx.createBuffer(1, n, sr);
    const x = buf.getChannelData(0); for (let i = 0; i < n; i++) x[i] = Math.random()*2-1; return buf;
  }
  function pad(freqs, t, len) {
    freqs.forEach((f, i) => [0,-7,7].forEach(c => {
      const o = ctx.createOscillator(); o.type = "sawtooth"; o.frequency.value = f; o.detune.value = c;
      const g = ctx.createGain(), bp = ctx.createBiquadFilter();
      bp.type = "lowpass"; bp.frequency.value = 1400 + i*120; bp.Q.value = 0.7;
      const peak = 0.06 / (i+1) / 3;
      g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(peak, t+0.6);
      g.gain.setValueAtTime(peak, t+len-0.8); g.gain.linearRampToValueAtTime(0, t+len);
      o.connect(bp).connect(g).connect(m.pad); o.start(t); o.stop(t+len+0.1);
    }));
  }
  function sub(t) {
    const o = ctx.createOscillator(); o.type = "sine"; o.frequency.value = 55;
    const g = ctx.createGain(); g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(0.42, t+0.02);
    g.gain.exponentialRampToValueAtTime(0.001, t+0.55);
    o.connect(g).connect(m.dry); o.start(t); o.stop(t+0.6);
  }
  function hat(t) {
    const s = ctx.createBufferSource(); s.buffer = m.noise;
    const hp = ctx.createBiquadFilter(); hp.type = "highpass"; hp.frequency.value = 7000 + Math.random()*2000;
    const g = ctx.createGain(); g.gain.setValueAtTime(0.08, t); g.gain.exponentialRampToValueAtTime(0.001, t+0.04);
    s.connect(hp).connect(g).connect(m.dry); s.start(t, Math.random()*0.4);
  }
  function snare(t) {
    const s = ctx.createBufferSource(); s.buffer = m.noise;
    const bp = ctx.createBiquadFilter(); bp.type = "bandpass"; bp.frequency.value = 1800; bp.Q.value = 0.6;
    const g = ctx.createGain(); g.gain.setValueAtTime(0.16, t); g.gain.exponentialRampToValueAtTime(0.001, t+0.12);
    s.connect(bp).connect(g).connect(m.verb); s.start(t, Math.random()*0.3);
  }
  function bar(idx) {
    const t0 = ctx.currentTime + 0.05, chord = CHORDS[idx % CHORDS.length], barLen = BEAT*4;
    pad(chord, t0, barLen);
    for (let b = 0; b < 4; b++) {
      const tb = t0 + b * BEAT;
      if (b === 0 || b === 2) sub(tb);
      if (b === 1 || b === 3) snare(tb + (Math.random()-0.5)*0.04);
      for (let s = 0; s < 4; s++) if (Math.random() < 0.55) hat(tb + s*BEAT/4);
    }
  }
  return () => {
    if (playing) { try { clearInterval(iv); ctx.close(); } catch(err){ window.MASTER_LOG?.warn?.("face_loops_music:stop", err); } playing = false; return false; }
    try {
      ctx = new (window.AudioContext || window.webkitAudioContext)();
      m = { dry: ctx.createGain(), pad: ctx.createGain(), verb: ctx.createGain(), conv: ctx.createConvolver(), noise: noise(1.0) };
      m.dry.gain.value = 0.9; m.pad.gain.value = 0.85; m.verb.gain.value = 0.6;
      m.conv.buffer = impulse(2.6, 2.4);
      const wet = ctx.createGain(); wet.gain.value = 0.45;
      m.pad.connect(m.conv); m.verb.connect(m.conv); m.conv.connect(wet).connect(ctx.destination);
      m.dry.connect(ctx.destination); m.pad.connect(ctx.destination);
      let i = 0; bar(i++); iv = setInterval(() => bar(i++), BEAT*4*1000);
      playing = true; return true;
    } catch (_) { return false; }
  };
})();

window._dillaBg = (() => {
  let ctx, master, padFilt, padGain, bassBus, kickBus, shelf, hatGain, conv, convGain;
  let playing = false, barIv = null, duckIv = null;
  const CHORDS = [
    [123.47, 146.83, 185.00, 220.00, 277.18],
    [82.41,  123.47, 196.00, 246.94, 329.63],
    [130.81, 164.81, 196.00, 246.94, 293.66],
    [92.50,  138.59, 184.99, 233.08, 277.18]
  ];
  const BPM = 88, BEAT = 60 / BPM, BAR = BEAT * 4, SWING = 0.16;
  function impulse(d, k) {
    const sr = ctx.sampleRate, n = (sr * d) | 0, b = ctx.createBuffer(2, n, sr);
    for (let c = 0; c < 2; c++) {
      const x = b.getChannelData(c);
      for (let i = 0; i < n; i++) x[i] = (Math.random()*2-1) * Math.pow(1 - i/n, k);
    }
    return b;
  }
  function noiseBuf(d) {
    const sr = ctx.sampleRate, n = (sr * d) | 0, b = ctx.createBuffer(1, n, sr);
    const x = b.getChannelData(0);
    for (let i = 0; i < n; i++) x[i] = Math.random()*2 - 1;
    return b;
  }
  function pad(freqs, when, len) {
    freqs.forEach(f => {
      [-7, 7].forEach(det => {
        const o = ctx.createOscillator();
        o.type = 'sawtooth'; o.frequency.value = f; o.detune.value = det;
        const g = ctx.createGain();
        g.gain.setValueAtTime(0, when);
        g.gain.linearRampToValueAtTime(0.05, when + 0.6);
        g.gain.linearRampToValueAtTime(0.04, when + len - 0.4);
        g.gain.linearRampToValueAtTime(0, when + len);
        o.connect(g).connect(padFilt);
        o.start(when); o.stop(when + len + 0.1);
      });
    });
  }
  function sub(when) {
    const o = ctx.createOscillator();
    o.type = 'sine';
    o.frequency.setValueAtTime(70, when);
    o.frequency.exponentialRampToValueAtTime(35, when + 0.06);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0, when);
    g.gain.linearRampToValueAtTime(0.95, when + 0.02);
    g.gain.exponentialRampToValueAtTime(0.001, when + 1.6);
    o.connect(g).connect(bassBus);
    o.start(when); o.stop(when + 1.7);
  }
  function kick(when, vel = 1.0) {
    const src = ctx.createBufferSource();
    src.buffer = noiseBuf(0.05);
    const clickHp = ctx.createBiquadFilter();
    clickHp.type = 'highpass'; clickHp.frequency.value = 2200;
    const clickG = ctx.createGain();
    clickG.gain.setValueAtTime(0.22 * vel, when);
    clickG.gain.exponentialRampToValueAtTime(0.001, when + 0.018);
    src.connect(clickHp).connect(clickG).connect(kickBus);
    src.start(when); src.stop(when + 0.05);
    const body = ctx.createOscillator();
    body.type = 'sine';
    body.frequency.setValueAtTime(150, when);
    body.frequency.exponentialRampToValueAtTime(42, when + 0.055);
    const bodyG = ctx.createGain();
    bodyG.gain.setValueAtTime(0, when);
    bodyG.gain.linearRampToValueAtTime(0.78 * vel, when + 0.004);
    bodyG.gain.exponentialRampToValueAtTime(0.001, when + 0.42);
    body.connect(bodyG).connect(kickBus);
    body.start(when); body.stop(when + 0.45);
  }
  function hat(when) {
    const src = ctx.createBufferSource(); src.buffer = noiseBuf(0.06);
    const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 7800;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.04, when);
    g.gain.exponentialRampToValueAtTime(0.001, when + 0.05);
    src.connect(hp).connect(g).connect(hatGain);
    src.start(when); src.stop(when + 0.08);
  }
  function rim(when) {
    const src = ctx.createBufferSource(); src.buffer = noiseBuf(0.04);
    const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 2000; bp.Q.value = 6;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.05, when);
    g.gain.exponentialRampToValueAtTime(0.001, when + 0.09);
    src.connect(bp).connect(g).connect(hatGain);
    src.start(when); src.stop(when + 0.1);
  }
  function setupBus() {
    master = ctx.createGain(); master.gain.value = 0; master.connect(ctx.destination);
    const lofi = ctx.createBiquadFilter(); lofi.type = 'lowpass'; lofi.frequency.value = 2200; lofi.Q.value = 0.7;
    lofi.connect(master);
    padFilt = ctx.createBiquadFilter(); padFilt.type = 'lowpass'; padFilt.frequency.value = 1700;
    padGain = ctx.createGain(); padGain.gain.value = 0.55;
    padFilt.connect(padGain).connect(lofi);
    hatGain = ctx.createGain(); hatGain.gain.value = 0.45;
    hatGain.connect(master);
    shelf = ctx.createBiquadFilter(); shelf.type = 'lowshelf'; shelf.frequency.value = 80; shelf.gain.value = 9;
    kickBus = ctx.createGain(); kickBus.gain.value = 0.88;
    kickBus.connect(shelf).connect(master);
    bassBus = ctx.createGain(); bassBus.gain.value = 0.72;
    bassBus.connect(shelf).connect(master);
    conv = ctx.createConvolver(); conv.buffer = impulse(2.4, 2.6);
    convGain = ctx.createGain(); convGain.gain.value = 0.20;
    padGain.connect(conv); conv.connect(convGain).connect(master);
  }
  function scheduleBar(bar, when) {
    const chord = CHORDS[(bar >> 1) % CHORDS.length];
    pad(chord, when, BAR + 0.2);
    kick(when, 1.0);
    kick(when + BEAT * 2 + BEAT * SWING * 0.35, 0.82);
    sub(when);
    sub(when + BEAT * 2);
    if (bar % 2 === 1) {
      kick(when + BEAT + BEAT * SWING * 0.6, 0.58);
      rim(when + BEAT * 2 + BEAT * SWING);
    }
    for (let i = 0; i < 8; i++) {
      const isOff = (i & 1) === 1;
      const t = when + (i * BEAT / 2) + (isOff ? BEAT * SWING * 0.5 : 0);
      if (Math.random() > (isOff ? 0.30 : 0.58)) hat(t);
    }
  }
// speakPickup() removed 2026-08-14: it spoke a random pick-up line 12s after
// the loop started and every 48s after that, unprompted. The music stays; the
// flirting does not. MASTER speaks when spoken to.
  return () => {
    if (playing) {
      playing = false;
      try { clearInterval(barIv); clearInterval(duckIv); } catch (err) { window.MASTER_LOG?.warn?.("face_loops_music:stop", err); }
      try { master?.gain.linearRampToValueAtTime(0, ctx.currentTime + 0.8); } catch (err) { window.MASTER_LOG?.warn?.("face_loops_music:fade_out", err); }
      setTimeout(() => { try { ctx?.close(); } catch (err) { window.MASTER_LOG?.warn?.("face_loops_music:close", err); } }, 900);
      return false;
    }
    try {
      ctx = (F_FACE_LOOPS.actx || window.MASTER_FACE?.actx || window.actx) || new (window.AudioContext || window.webkitAudioContext)();
      if (ctx.state === 'suspended') ctx.resume().catch(()=>{});
      setupBus();
      playing = true;
      let bar = 0;
      const t0 = ctx.currentTime + 0.25;
      scheduleBar(bar++, t0);
      barIv = setInterval(() => { if (!playing) return; scheduleBar(bar++, ctx.currentTime + 0.05); }, BAR * 1000);
      duckIv = setInterval(() => {
        if (!playing) return;
        const speaking = !!(F_FACE_TTS?.playing);
        const target = speaking ? 0.025 : 0.14;
        try { master.gain.linearRampToValueAtTime(target, ctx.currentTime + 0.5); } catch (err) { window.MASTER_LOG?.warn?.("face_loops_music:duck_ramp", err); }
      }, 500);
      master.gain.setValueAtTime(0, ctx.currentTime);
      master.gain.linearRampToValueAtTime(0.14, ctx.currentTime + 5);
      return true;
    } catch (err) { window.MASTER_LOG?.warn?.("face_loops_music:start", err); return false; }
  };
})();
