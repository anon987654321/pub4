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

  // Unified swipe gestures (right edge for nav, left for hide, down for content action/Osman read)
  // Supports touch + desktop mouse drag simulation for creative cross-device
  let lastTouch = { x: 0, y: 0, time: 0 };
  const startGesture = (x, y) => {
    lastTouch = { x, y, time: Date.now() };
    if (innerWidth - x < 48) body.dataset.rightEdge = '1';
  };
  const endGesture = (x, y) => {
    const dx = x - lastTouch.x;
    const dy = y - lastTouch.y;
    const dt = Date.now() - lastTouch.time;
    delete body.dataset.rightEdge;

    if (dx > 60 && dt < 400 && lastTouch.x > innerWidth - 80) {
      const sidebar = document.querySelector('.sidebar, nav, .app-shell > aside');
      if (sidebar) sidebar.classList.add('revealed');
    } else if (dx < -100) {
      document.querySelectorAll('.revealed, .sidebar.revealed').forEach(el => el.classList.remove('revealed'));
    } else if (dy > 80 && Math.abs(dx) < 50) {
      const main = document.querySelector('main, .app-shell');
      if (main) main.style.opacity = '0.7';
      setTimeout(() => { if (main) main.style.opacity = ''; }, 300);
      if (window.MASTERMinimalUI?.triggerOsman) window.MASTERMinimalUI.triggerOsman('current content');
      else if (window.startOsmanVoice) window.startOsmanVoice();
    }
  };

  // Touch
  document.addEventListener('touchstart', e => startGesture(e.touches[0].clientX, e.touches[0].clientY), { passive: true });
  document.addEventListener('touchend', e => endGesture(e.changedTouches[0].clientX, e.changedTouches[0].clientY), { passive: true });

  // Desktop mouse drag sim (for testing/dev creative use)
  let mouseDown = false;
  document.addEventListener('mousedown', e => { mouseDown = true; startGesture(e.clientX, e.clientY); });
  document.addEventListener('mouseup', e => { if (mouseDown) { mouseDown = false; endGesture(e.clientX, e.clientY); } });
  document.addEventListener('mouseleave', () => { mouseDown = false; });

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
          // Innovative cam "face tracking": central brightness as proxy for user face position
          // Drives CSS vars for parallax, and syncs to MASTER particle face for "eye contact"
          document.documentElement.style.setProperty('--cam-tilt-x', nx.toFixed(2));
          document.documentElement.style.setProperty('--cam-tilt-y', ny.toFixed(2));
          if (window.State) {
            window.State.mouseX = nx * 0.8;
            window.State.mouseY = ny * 0.6;
            // Creative: slight arousal on face when user "looks" at it
            if (Math.abs(nx) < 0.3 && Math.abs(ny) < 0.3) window.State.pulse = Math.max(window.State.pulse || 0, 0.4);
          }
          // Optional: tilt main content subtly for "presence" feel
          const main = document.querySelector('main, .app-shell');
          if (main) main.style.transform = `translate(${nx * -2}px, ${ny * -1}px)`;
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
          // Trigger Osman via global hook or fetch to /tts (MASTER backend or shared)
          if (window.MASTERMinimalUI?.triggerOsman) {
            window.MASTERMinimalUI.triggerOsman(command);
          } else if (window.speakWithOsman) {
            window.speakWithOsman(command);
          } else {
            // Fallback: browser speech (or could fetch /tts with Osman style if endpoint exists)
            const utter = new SpeechSynthesisUtterance(`Osman says: ${command}`);
            speechSynthesis.speak(utter);
            // Visual cue in face if present
            if (window.State) window.State.pulse = 0.8;
          }
        }
      }
    };

    // Expose to start voice mode
    window.startOsmanVoice = () => rec.start();
  }
}

export default { initMinimalUI };

// Auto-initialize on module load for <script type="module" src> includes in all apps
// (brgen uses manual import in some cases for flexibility)
if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  const autoInit = () => {
    if (typeof initMinimalUI === 'function') {
      initMinimalUI();
    }
  };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', autoInit, { once: true });
  } else {
    autoInit();
  }
}