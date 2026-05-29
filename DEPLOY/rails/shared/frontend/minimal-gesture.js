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

  // Right edge swipe for nav
  document.addEventListener('touchstart', e => {
    if (innerWidth - e.touches[0].clientX < 48) body.dataset.rightEdge = '1';
  }, { passive: true });
  document.addEventListener('touchend', () => delete body.dataset.rightEdge);

  // Camera face tracking (same as MASTER web)
  async function startCamFace() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'user', width: 200, height: 150 } });
      const v = document.createElement('video'); v.srcObject = stream; v.play();
      const c = document.createElement('canvas'); const ctx = c.getContext('2d');
      c.width = 100; c.height = 75;
      setInterval(() => {
        if (v.readyState < 2) return;
        ctx.drawImage(v, 0, 0, c.width, c.height);
        // ... (simplified brightness center tracking, can be expanded per app)
      }, 200);
    } catch (_) {}
  }
  if (matchMedia('(pointer: coarse)').matches) setTimeout(startCamFace, 1100);

  // Osman voice trigger (double-tap logo or long-press face area)
  let lastTap = 0;
  document.addEventListener('click', (e) => {
    const logo = e.target.closest('.top-right-logo, .brand');
    if (logo) {
      const now = Date.now();
      if (now - lastTap < 280) {
        if (window.MASTERMinimalUI?.triggerOsman) window.MASTERMinimalUI.triggerOsman('last');
        else if (window.speakWithOsman) window.speakWithOsman();
      }
      lastTap = now;
    }
  });
}

export default { initMinimalUI };