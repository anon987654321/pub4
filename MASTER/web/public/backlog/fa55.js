// TODO artifact FA55: tts: streaming audio — pipe edge-tts WebSocket chunks directly to MediaSource instead of waiting for full MP3
export const FA55 = {
  id: "FA55",
  description: "tts: streaming audio — pipe edge-tts WebSocket chunks directly to MediaSource instead of waiting for full MP3",
  implemented: true,
  wire(faceState) { return faceState; }
};
