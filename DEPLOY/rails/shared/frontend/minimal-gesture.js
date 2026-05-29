// Shared ultra-minimal gesture + sensor + voice layer for all apps
// Syncs with MASTER web face philosophy: almost nothing visible, gestures + sensors + Osman TTS

export function initMinimalUI() {
  const body = document.body;
  body.classList.add('zen-minimal');

  // Swipe up from bottom reveals primary input / console
  let sy = 0;
  document.addEventListener('touchstart', e => { sy = e.touches[0].clientY; }, { passive: true });
  document.addEventListener('touchend', e => {
    if (e.changedTouches[0].clientY - sy < -85) {
      document.querySelectorAll('[data-minimal-reveal="console"], #zsh, .primary-input').forEach(el => el.classList.add('revealed'));
    }
  });

  // Right edge swipe for nav (e.g. reveal sidebar in brgen-style apps)
  let swipeStartX = 0;
  document.addEventListener('touchstart', e => {
    swipeStartX = e.touches[0].clientX;
    if (innerWidth - swipeStartX < 48) body.dataset.rightEdge = '1';
  }, { passive: true });
  document.addEventListener('touchend', e => {
    const delta = e.changedTouches[0].clientX - swipeStartX;
    delete body.dataset.rightEdge;
    if (delta > 60) {
      // Swipe right from edge -> reveal sidebar/nav
      const sidebar = document.querySelector('.sidebar, nav, .app-shell > aside');
      if (sidebar) sidebar.classList.add('revealed');
    }
  }, { passive: true });

  // Swipe left anywhere to hide revealed elements (minimal reset)
  document.addEventListener('touchend', e => {
    if (e.changedTouches[0].clientX - swipeStartX < -100) {
      document.querySelectorAll('.revealed, .sidebar.revealed').forEach(el => el.classList.remove('revealed'));
    }
  });

  // Advanced cam tracking + sensors (innovative mobile-first, synced with MASTER face)
  async function startCamFace() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'user', width: 160, height: 120 } });
      const v = document.createElement('video'); v.srcObject = stream; v.play();
      const c = document.createElement('canvas'); const ctx = c.getContext('2d', { willReadFrequently: true });
      c.width = 80; c.height = 60;

      setInterval(() => {
        if (v.readyState < 2) return;
        ctx.drawImage(v, 0, 0, c.width, c.height);
        const data = ctx.getImageData(0, 0, c.width, c.height).data;
        let sumX = 0, sumY = 0, count = 0;
        for (let i = 0; i < data.length; i += 4) {
          if ((data[i] + data[i+1] + data[i+2]) / 3 > 60) {
            const p = i / 4;
            sumX += p % c.width;
            sumY += (p / c.width) | 0;
            count++;
          }
        }
        if (count > 20) {
          const nx = (sumX / count / c.width - 0.5) * 2;
          const ny = (sumY / count / c.height - 0.5) * 1.5;
          // Subtle UI reaction (e.g. shift subtle elements)
          document.documentElement.style.setProperty('--cam-tilt-x', nx.toFixed(2));
          document.documentElement.style.setProperty('--cam-tilt-y', ny.toFixed(2));
          // If MASTER face present, influence it
          if (window.State) { window.State.mouseX = nx * 0.8; window.State.mouseY = ny * 0.6; }
        }
      }, 140);
    } catch (_) {}
  }
  if (matchMedia('(pointer: coarse)').matches) setTimeout(startCamFace, 900);

  // Device sensors for creative control (tilt = subtle parallax, shake = clear/refresh)
  if (window.DeviceOrientationEvent) {
    window.addEventListener('deviceorientation', (e) => {
      const tx = (e.gamma || 0) / 45;
      const ty = ((e.beta || 0) - 45) / 45;
      document.documentElement.style.setProperty('--sensor-tilt-x', tx.toFixed(2));
      document.documentElement.style.setProperty('--sensor-tilt-y', ty.toFixed(2));
    }, { passive: true });
  }
  if (window.DeviceMotionEvent) {
    let lastShake = 0;
    window.addEventListener('devicemotion', (e) => {
      const acc = e.accelerationIncludingGravity;
      if (!acc) return;
      const force = Math.abs(acc.x) + Math.abs(acc.y) + Math.abs(acc.z);
      if (force > 18 && Date.now() - lastShake > 800) {
        lastShake = Date.now();
        // Shake to clear or trigger voice
        document.querySelectorAll('.zen-minimal .revealed').forEach(el => el.classList.remove('revealed'));
        if (window.MASTERMinimalUI?.triggerOsman) window.MASTERMinimalUI.triggerOsman('refresh');
      }
    }, { passive: true });
  }

  // Osman voice (double-tap brand or long-press on face/canvas)
  let lastTap = 0;
  document.addEventListener('click', (e) => {
    const logo = e.target.closest('.top-right-logo, .brand');
    if (logo) {
      const now = Date.now();
      if (now - lastTap < 260) {
        if (window.MASTERMinimalUI?.triggerOsman) window.MASTERMinimalUI.triggerOsman('last');
        else if (window.speakWithOsman) window.speakWithOsman();
      }
      lastTap = now;
    }
  });

  // Voice commands: "Osman, [command]" using Web Speech API (triggers Osman TTS backend if available)
  if ('SpeechRecognition' in window || 'webkitSpeechRecognition' in window) {
    const SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
    const rec = new SpeechRec();
    rec.continuous = false;
    rec.interimResults = false;
    rec.lang = 'en-US';

    document.addEventListener('keydown', e => {
      if (e.key === '/' && document.activeElement.tagName === 'BODY') {
        e.preventDefault();
        try { rec.start(); } catch (_) {}
      }
    });

    rec.onresult = (event) => {
      const transcript = event.results[0][0].transcript.toLowerCase();
      if (transcript.includes('osman') || transcript.includes('voice')) {
        const command = transcript.replace(/osman|voice|hey|ok/gi, '').trim();
        if (command) {
          // Trigger Osman via global hook or fetch to /tts if in MASTER context
          if (window.MASTERMinimalUI?.triggerOsman) {
            window.MASTERMinimalUI.triggerOsman(command);
          } else if (window.speakWithOsman) {
            window.speakWithOsman(command);
          } else {
            // Fallback browser speech + visual cue
            const utter = new SpeechSynthesisUtterance(command);
            speechSynthesis.speak(utter);
          }
        }
      }
    };

    // Expose to start voice mode
    window.startOsmanVoice = () => rec.start();
  }
}

export default { initMinimalUI };