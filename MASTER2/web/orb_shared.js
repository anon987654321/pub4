// Shared constants and functions for all orb visualizations
// Extracted from orb_blob.html, orb_particle.html, orb_3d.html, orb_retro.html

// State parameters for different modes
const STATE_PARAMS = {
  idle: { decay: 0.05, reactivity: 0.3, speed: 0.5 },
  thinking: { decay: 0.12, reactivity: 0.6, speed: 0.8 },
  speaking: { decay: 0.20, reactivity: 1.0, speed: 1.0 }
};

// Continuous shade function (mint color gradient)
function shade(t) {
  t = Math.max(0, Math.min(1, t));
  const r = Math.round(5 + t * 85);
  const g = Math.round(5 + t * 235);
  const b = Math.round(5 + t * 177);
  return "rgb(" + r + "," + g + "," + b + ")";
}

// State management variables (initialized to defaults)
// Note: Declared with var to allow reassignment in main scripts
if (typeof state === 'undefined') var state = 'idle';
if (typeof audioLevel === 'undefined') var audioLevel = 0;

// Common message handler setup function
// Call this if you don't need custom message handling
function setupDefaultMessageHandler() {
  window.addEventListener('message', function(e) {
    if (e.data && e.data.type === 'state') state = e.data.mode;
    if (e.data && e.data.type === 'audio') audioLevel = e.data.level;
  });
}
