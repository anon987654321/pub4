const F_FACE_MINIMAL = window.MASTER_FACE || {};
const F_FACE_STATE = F_FACE_MINIMAL.State || window.State;

(function bootstrapUltraMinimal() {
  const body = document.body;
  if (!body.classList.contains('zen')) body.classList.add('zen');

  let startY = 0;
  document.addEventListener('touchstart', e => { startY = e.touches[0].clientY; }, { passive: true });
  document.addEventListener('touchend', e => {
    if (e.changedTouches[0].clientY - startY < -90) {
      const zsh = document.getElementById('zsh');
      if (zsh) zsh.classList.add('revealed');
      if (window.FACE3D_ACTIVE || window.MASTER_FACE_BLEND) F_FACE_STATE.pulse = 0.7;
    }
  }, { passive: true });

  document.addEventListener('touchstart', e => {
    if (innerWidth - e.touches[0].clientX < 55) body.dataset.edgeSwipe = '1';
  }, { passive: true });
  document.addEventListener('touchend', () => delete body.dataset.edgeSwipe);

  document.addEventListener('mousemove', (e) => {
    if (!body.classList.contains('zen')) return;
    if (innerHeight - e.clientY < 56) body.dataset.edgeHover = '1';
    else delete body.dataset.edgeHover;
    resetZenHide();
  }, { passive: true });

  let zenIdleTimer = null;
  function resetZenHide() {
    clearTimeout(zenIdleTimer);
    body.classList.remove('zen-hidden');
    zenIdleTimer = setTimeout(() => {
      if (!body.classList.contains('zen') || body.dataset.edgeHover === '1') return;
      body.classList.add('zen-hidden');
    }, 4500);
  }
  ['pointerdown', 'keydown', 'touchstart'].forEach((ev) => document.addEventListener(ev, resetZenHide, { passive: true }));
  resetZenHide();

  const cvEl = document.getElementById('face');
  if (cvEl) {
    let t = null;
    cvEl.addEventListener('pointerdown', () => {
      t = setTimeout(() => {
        if (window._chatSpeakLast) window._chatSpeakLast();
        else if (window.sendMessage) window.sendMessage('/voice last osman dramatic');
        F_FACE_STATE.pulse = 1.1;
      }, 480);
    });
    ['pointerup', 'pointerleave'].forEach(ev => cvEl.addEventListener(ev, () => clearTimeout(t)));
  }

  async function enableCamTracking() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user', width: 240, height: 180 }
      });
      const v = document.createElement('video');
      v.srcObject = stream; v.play();
      const c = document.createElement('canvas');
      const ctx = c.getContext('2d', { willReadFrequently: true });
      c.width = 120; c.height = 90;

      setInterval(() => {
        if (!v || v.readyState < 2) return;
        ctx.drawImage(v, 0, 0, c.width, c.height);
        const d = ctx.getImageData(0, 0, c.width, c.height).data;
        let sx = 0, sy = 0, n = 0;
        for (let i = 0; i < d.length; i += 4) {
          if ((d[i] + d[i+1] + d[i+2]) / 3 > 65) {
            const p = i / 4;
            sx += p % c.width;
            sy += (p / c.width) | 0;
            n++;
          }
        }
        if (n > 40) {
          const nx = (sx / n / c.width - 0.5) * 2.1;
          const ny = (sy / n / c.height - 0.5) * 1.3;
          F_FACE_STATE.mouseX = nx;
          F_FACE_STATE.mouseY = ny;
          if (Math.abs(nx) < 0.3 && Math.abs(ny) < 0.3) {
            F_FACE_STATE.pulse = Math.max(F_FACE_STATE.pulse || 0, 0.5);
          }
        }
      }, 160);
    } catch (_) {}
  }
  if (F_FACE_STATE.coarsePointer) setTimeout(enableCamTracking, 900);

  window.MASTERMinimalUI = {
    enableCam: enableCamTracking,
    revealConsole: () => {
      const z = document.getElementById('zsh');
      if (z) z.classList.add('revealed');
    },
    triggerOsman: (text) => {
      if (window.sendMessage) window.sendMessage(`/voice ${text || 'last'} osman`);
    }
  };

  if ('SpeechRecognition' in window || 'webkitSpeechRecognition' in window) {
    const SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
    const rec = new SpeechRec();
    rec.continuous = false;
    rec.lang = 'en-US';
    rec.onresult = (ev) => {
      const t = ev.results[0][0].transcript.toLowerCase();
      if (t.includes('osman')) {
        const cmd = t.replace(/osman|hey|ok/gi, '').trim();
        if (cmd && window.sendMessage) window.sendMessage(`/voice ${cmd} osman`);
      }
    };
    document.addEventListener('keydown', e => {
      if (e.key === '?') { e.preventDefault(); rec.start(); }
    });
    window.startOsmanVoice = () => rec.start();
  }
})();
