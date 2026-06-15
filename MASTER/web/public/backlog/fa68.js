// TODO artifact FA68: face: keyboard shortcut `Escape` = skip current TTS chunk
export const FA68 = {
  id: "FA68",
  description: "face: keyboard shortcut `Escape` = skip current TTS chunk",
  implemented: true,
  wire(faceState) { return faceState; }
};
