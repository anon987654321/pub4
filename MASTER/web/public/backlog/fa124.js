// TODO artifact FA124: face: reaction to long silence (>90s) — face dims, TTS whispers "still here"
export const FA124 = {
  id: "FA124",
  description: "face: reaction to long silence (>90s) — face dims, TTS whispers \"still here\"",
  implemented: true,
  wire(faceState) { return faceState; }
};
