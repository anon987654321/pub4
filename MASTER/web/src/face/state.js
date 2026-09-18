/**
 * Face State & Constants
 * Consolidated from face.part1.txt
 */
export const FACE_PHOSPHOR_DECAY = 0.88;
export const FACE_RENDER_SCALE = 0.72;
export const FACE_BUFFER_MAX_W = 960;
export const FACE_BUFFER_MAX_H = 640;

export const State = {
  mode: 'idle', mood: 'idle', model: '', modelName: '',
  voiceName: '',
  voiceLocked: false,
  lastTouch: performance.now(), confidence: 1.0,
  tiltX: 0, tiltY: 0, mouseX: 0, mouseY: 0,
  parX: 0, parY: 0,
  viseme: 'neutral', visemeAmp: 0,
  flash: 0, shake: 0, pulse: 0, sttActive: false, sttDuck: 0, profileOverride: null,
  moodArc: null, emotionalGhosts: [],
  calmStareUntil: 0, nervousUntil: 0, breath: 1.0,
  surpriseY: 0, ripplePhase: -1, rain: 0,
  pinchScale: 1.0, idleAlphaDrift: 0,
  modelSwitch: 0,
  questionPulse: 0,
  sleeping: false, sleepMuted: false,
  voiceMode: false, wakeArmed: false,
  hidden: document.hidden, reducedMotion: matchMedia('(prefers-reduced-motion: reduce)').matches,
  coarsePointer: matchMedia('(pointer: coarse)').matches,
  highContrast: new URLSearchParams(window.location.search).get('hc') === '1',
  contrastMore: matchMedia("(prefers-contrast: more)").matches
};
State.expressionCurrent = {};
State.expressionTarget = {};

export const TINT = {
  idle: { r: 1, g: 1, b: 1 }, // Simplified for module
  claude: { r: 1, g: 1, b: 1 }, deepseek: { r: 1, g: 1, b: 1 }, gemini: { r: 1, g: 1, b: 1 }, gpt: { r: 1, g: 1, b: 1 },
  tense: { r: 1, g: 1, b: 1 }, curious: { r: 1, g: 1, b: 1 }, focused: { r: 1, g: 1, b: 1 }, weary: { r: 1, g: 1, b: 1 },
  pass: { r: 1, g: 1, b: 1 }, veto: { r: 1, g: 1, b: 1 }, unclear: { r: 1, g: 1, b: 1 }
};
