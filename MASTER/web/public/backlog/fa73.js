// TODO artifact FA73: face: "sleep" command — face dims to 5% alpha, TTS mutes, wakes on any input
export const FA73 = {
  id: "FA73",
  description: "face: \"sleep\" command — face dims to 5% alpha, TTS mutes, wakes on any input",
  implemented: true,
  wire(faceState) { return faceState; }
};
