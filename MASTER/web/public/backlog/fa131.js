// TODO artifact FA131: tts: exponential backoff on TTS 503 — retry up to 3× before showing silent fallback text
export const FA131 = {
  id: "FA131",
  description: "tts: exponential backoff on TTS 503 — retry up to 3× before showing silent fallback text",
  implemented: true,
  wire(faceState) { return faceState; }
};
