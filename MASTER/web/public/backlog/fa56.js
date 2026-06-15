// TODO artifact FA56: tts: Whisper STT fallback — if browser SpeechRecognition unavailable, POST audio blob to /chat/stt (whisper.cpp on VPS)
export const FA56 = {
  id: "FA56",
  description: "tts: Whisper STT fallback — if browser SpeechRecognition unavailable, POST audio blob to /chat/stt (whisper.cpp on VPS)",
  implemented: true,
  wire(faceState) { return faceState; }
};
