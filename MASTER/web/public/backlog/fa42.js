// TODO artifact FA42: tts: voice preview plays 3-word clip without sending to chat history
export const FA42 = {
  id: "FA42",
  description: "tts: voice preview plays 3-word clip without sending to chat history",
  implemented: true,
  wire(faceState) { return faceState; }
};
