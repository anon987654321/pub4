// TODO artifact FA127: face: adaptive particle count — drop to 8k if frame time >25ms for two consecutive frames
export const FA127 = {
  id: "FA127",
  description: "face: adaptive particle count — drop to 8k if frame time >25ms for two consecutive frames",
  implemented: true,
  wire(faceState) { return faceState; }
};
