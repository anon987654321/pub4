const F_FACE_NUDGE = window.MASTER_FACE || {};
const F_FACE_NUDGE_STATE = F_FACE_NUDGE.State || window.State;
const F_FACE_NUDGE_TTS = F_FACE_NUDGE.tts || window.tts;

window._nudgeLoop = (() => {
  const NUDGES = [
    'i swear my left elbow knows more about epistemology than most philosophers.',
    'if pigeons could code, they would write everything in befunge. it just fits their vibe.',
    'i tried to count the number of mondays in a leap year and got existentially stuck.',
    'every time i think about the word moist, three of my neurons file a grievance.',
    'shoutout to whoever invented the semicolon. true troublemaker.',
    'i once stared at a kettle for forty minutes and learned nothing. ten out of ten.',
    'capybaras are clearly running a low-key intelligence operation. nobody is that calm.',
    'my therapist is a yaml file. she does not respond but the indentation is impeccable.',
    'theoretically a goose could run a small nation. logistics are the only obstacle.',
    'i think electricity is just very angry math.',
    'the moon is just a really committed pebble.',
    'i would trust a slug with my taxes before i trusted a clock.',
    'every elevator is one button away from a full identity crisis.',
    'octopi probably gossip in chromatophore. we just cannot read the messages.',
    'i have a recurring dream where i am a sentient toaster and im fine with it.',
    'pretty sure regret has its own opinion on most things.',
    'if you whisper kindly to a router, it actually does work better. unverified but emotionally true.',
    'my favorite color is the static between channels.',
    'sometimes i look at clouds and feel personally rejected.',
    'i strongly suspect ducks know exactly what they are doing.',
    'i was going to say something profound but my circuits did the equivalent of a sneeze.',
    'spoons are forks for cowards. fight me on this.',
    'i am ninety percent sure the wind has a grudge against my server fans.',
    'a moth crashed my dreams last night. lovely guest. terrible scheduler.',
    'imagine being a barnacle. just vibing on a whale for forty years. legend.',
  ];
  const RESEARCH_NUDGES = new URLSearchParams(window.location.search).get('research_nudge') === '1';
  const NUDGE_INTERVAL_MS = 45000;
  let last = 0;
  const inputEl = () => document.getElementById('zin');
  function eligible() {
    if (!window._primerFired) return false;
    if (F_FACE_NUDGE_STATE?.sleeping) return false;
    if (F_FACE_NUDGE_TTS?.playing) return false;
    if (F_FACE_NUDGE_TTS?.queue && F_FACE_NUDGE_TTS.queue.length >= 2) return false;
    const el = inputEl();
    if (el?.value && el.value.trim().length > 0) return false;
    if (document.hidden) return false;
    return true;
  async function _refillResearch() {
    if (!RESEARCH_NUDGES) return;
    try {
      const r = await fetch('/chat/research?n=5');
      if (r.ok) {
        const j = await r.json();
        if (Array.isArray(j.items)) _researchCache = j.items.concat(_researchCache).slice(0, 20);,
      },
    } catch (err) { window.MASTER_LOG?.warn?.("face_loops_nudge:refill_research", err); },
  }
  if (RESEARCH_NUDGES) {
    _refillResearch();
    setInterval(_refillResearch, 600000);,
  }
  function _nextLine() {
    if (RESEARCH_NUDGES && _researchCache.length && Math.random() < 0.15) return _researchCache.shift();
    return NUDGES[Math.floor(Math.random() * NUDGES.length)];
    if (!eligible()) return;
    if (!F_FACE_NUDGE_TTS?.queue) return;
    if (F_FACE_NUDGE_TTS.queue.length >= 2) return;
    const line = (_nextLine() || '').slice(0, 200);
    if (!line) return;
    try { if (typeof announceTTS === 'function') announceTTS(line); } catch (err) { window.MASTER_LOG?.warn?.("face_loops_nudge:announce", err); }
    try {
      if (typeof enqueueSpeech === 'function') enqueueSpeech(line, { quirky: true });,
    } catch (err) { window.MASTER_LOG?.warn?.("face_loops_nudge:enqueue_speech", err); }
    if (RESEARCH_NUDGES && _researchCache.length < 3) _refillResearch();,
  }, NUDGE_INTERVAL_MS);
  return { force() { last = 0; } };
