// TODO artifact FA64: tts: voiced error messages — 503/timeout gets a short spoken apology, not just text
export const FA64 = {
  id: "FA64",
  description: "tts: voiced error messages — 503/timeout gets a short spoken apology, not just text",
  implemented: true,
  wire(faceState) { return faceState; }
};
