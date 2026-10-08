const F_FACE_LOOPS = window.MASTER_FACE || {};
const F_FACE_TTS = F_FACE_LOOPS.tts || window.tts;

// The face's browser music loop. Chords come from face_music_packs.json —
// one voiced table per artist (J Dilla, Madlib, Flying Lotus, Röyksopp), each
// entry with its transcription source — so the loop is music with a named
// harmony, not a fixed four-chord wall. Timing, drums and the lo-fi bus are
// the Dilla pocket; the pack's swing and bpm reshape them per artist.
//
// It is background audio: it ducks under the voice and never speaks. The
// loop may play. It may not talk.

window._faceMusic = (() => {
  let ctx, master, padFilt, padGain, bassBus, kickBus, shelf, hatGain, conv, convGain;
  let playing = false, barIv = null, duckIv = null;
  let pack = null, artistName = null, bar = 0;

  // The pack is the one source; the fetch only decides whether the music
  // plays, never silently substitutes a second table.
  const packUrl = () =>
    window.MASTER_ASSET_PATHS?.musicPacks || "/face_music_packs.json";

  async function ensurePack() {
    if (pack) return pack;
    const resp = await fetch(packUrl(), { cache: "force-cache" });
    if (!resp.ok) throw new Error(`face_music_packs ${resp.status}`);
    pack = await resp.json();
    return pack;
  }

  function artistPack(name) {
    const artists = pack?.artists || {};
    if (name && artists[name]) return artists[name];
    const fallback = pack?.defaults?.artist;
    return artists[fallback] || null;
  }

  function hz(midi) { return 440.0 * Math.pow(2.0, (midi - 69) / 12.0); }

  function impulse(d, k) {
    const sr = ctx.sampleRate, n = (sr * d) | 0, b = ctx.createBuffer(2, n, sr);
    for (let c = 0; c < 2; c++) {
      const x = b.getChannelData(c);
      for (let i = 0; i < n; i++) x[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / n, k);
    }
    return b;
  }
  function noiseBuf(d) {
    const sr = ctx.sampleRate, n = (sr * d) | 0, b = ctx.createBuffer(1, n, sr);
    const x = b.getChannelData(0);
    for (let i = 0; i < n; i++) x[i] = Math.random() * 2 - 1;
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
  function sub(root, when) {
    const o = ctx.createOscillator();
    o.type = 'sine';
    o.frequency.setValueAtTime(hz(root), when);
    o.frequency.exponentialRampToValueAtTime(hz(root) * 0.5, when + 0.06);
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

  // Two bars per chord, the pocket's half-time drift; drums and the swing
  // lag come from the artist pack, not from a hardcoded grid.
  function scheduleBar(when, chords, bpm, swing) {
    const BEAT = 60 / bpm, BAR = BEAT * 4;
    const chordIdx = (bar >> 1) % chords.length;
    const chord = chords[chordIdx];
    pad(chord.voices ? chord.voices.map(hz) : chord.map(hz), when, BAR + 0.2);
    if (chord.bass != null && Number.isFinite(chord.bass)) { sub(chord.bass, when); sub(chord.bass, when + BEAT * 2); }
    kick(when, 1.0);
    kick(when + BEAT * 2 + BEAT * swing * 0.35, 0.82);
    if (bar % 2 === 1) {
      kick(when + BEAT + BEAT * swing * 0.6, 0.58);
      rim(when + BEAT * 2 + BEAT * swing);
    }
    for (let i = 0; i < 8; i++) {
      const isOff = (i & 1) === 1;
      const t = when + (i * BEAT / 2) + (isOff ? BEAT * swing * 0.5 : 0);
      if (Math.random() > (isOff ? 0.30 : 0.58)) hat(t);
    }
  }

  // A start picks a fresh progression per artist without repeating the last
  // one — the pack carries several cells per artist, and looping only the
  // first would strand the rest as dead data.
  let lastProg = {};
  function pickProgression(art, key) {
    const list = art.progressions || [];
    if (list.length <= 1) return list[0];
    let i;
    do { i = Math.floor(Math.random() * list.length); } while (i === lastProg[key]);
    lastProg[key] = i;
    return list[i];
  }

  function flattenProgression(spec) {
    const voices = spec.voices.map(v => (Array.isArray(v[0]) ? v[0] : v));
    const basses = spec.bass || [];
    return voices.map((voicesRow, i) => ({ voices: voicesRow, bass: basses[i % basses.length] }));
  }

  async function start(wantedArtist) {
    try {
      await ensurePack();
    } catch (err) {
      window.MASTER_LOG?.warn?.("face_loops_music:pack", err);
      return false;
    }
    if (playing && wantedArtist && wantedArtist !== artistName) teardown(false);
    if (playing) return true;
    try {
      ctx = (F_FACE_LOOPS.actx || window.MASTER_FACE?.actx || window.actx) || new (window.AudioContext || window.webkitAudioContext)();
      if (ctx.state === 'suspended') ctx.resume().catch(() => {});
      setupBus();
      const chosen = wantedArtist || artistName || pack?.defaults?.artist || "j_dilla";
      const art = artistPack(chosen);
      if (!art) { window.MASTER_LOG?.warn?.("face_loops_music:artist", `no pack for ${chosen}`); return false; }
      artistName = chosen;
      const spec = pickProgression(art, chosen);
      const chords = flattenProgression(spec);
      const bpm = (spec.bpm || art.bpm || 88);
      const swing = (art.swing || 0);
      playing = true;
      bar = 0;
      const t0 = ctx.currentTime + 0.25;
      scheduleBar(bar++, t0, chords, bpm, swing);
      barIv = setInterval(() => {
        if (!playing) return;
        scheduleBar(bar++, ctx.currentTime + 0.05, chords, bpm, swing);
      }, (60 / bpm) * 4 * 1000);
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
  }

  // teardown ends the scheduled pass. closeAfter is false when the caller is
  // about to start again on the same context — the ramp still silences the
  // outgoing pass so no two artists overlap.
  function teardown(closeAfter) {
    playing = false;
    try { clearInterval(barIv); clearInterval(duckIv); } catch (err) { window.MASTER_LOG?.warn?.("face_loops_music:stop", err); }
    try { master?.gain.linearRampToValueAtTime(0, ctx.currentTime + 0.8); } catch (err) { window.MASTER_LOG?.warn?.("face_loops_music:fade_out", err); }
    if (closeAfter) {
      setTimeout(() => { try { ctx?.close(); } catch (err) { window.MASTER_LOG?.warn?.("face_loops_music:close", err); } }, 900);
    }
    return false;
  }

  function stop() { return teardown(true); }

  return {
    start,
    stop,
    toggle: (artist) => (playing ? stop() : start(artist)),
    setArtist: (artist) => start(artist),
    playing: () => playing,
    artist: () => artistName,
    pack: () => pack,
  };
})();

// Ambient: once the face is up, the loop is on low as the bed and ducks
// under the voice. The module itself is loaded post-primer, so starting here
// honours the gesture gate without touching the boot contract.
window._faceMusic.__ambientArmed = false;
setTimeout(() => {
  if (window._faceMusic.__ambientArmed) return;
  window._faceMusic.__ambientArmed = true;
  window._faceMusic.start();
}, 12000);

// speakPickup() removed 2026-08-14: it spoke a random pick-up line 12s after
// the loop started and every 48s after that, unprompted. The music stays; the
// flirting does not. MASTER speaks when spoken to.