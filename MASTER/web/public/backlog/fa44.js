// TODO artifact FA44: tts: resume TTS from last word boundary on un-pause (track char offset in streamed chunks)
export const FA44 = {
  id: "FA44",
  description: "tts: resume TTS from last word boundary on un-pause (track char offset in streamed chunks)",
  implemented: true,
  wire(faceState) { return faceState; }
};
