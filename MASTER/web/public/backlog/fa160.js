// TODO artifact FA160: face: vertex flicker — each vertex independently flickers at 0.5-2Hz with 8% amplitude; organic phosphor instability, no
export const FA160 = {
  id: "FA160",
  description: "face: vertex flicker — each vertex independently flickers at 0.5-2Hz with 8% amplitude; organic phosphor instability, not synchronised",
  implemented: true,
  wire(faceState) { return faceState; }
};
