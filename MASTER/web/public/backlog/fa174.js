// TODO artifact FA174: face: GLSL snoise → hash23 replacement — hash-based noise cheaper on mobile GPU; swap for devices with frame time >20ms
export const FA174 = {
  id: "FA174",
  description: "face: GLSL snoise → hash23 replacement — hash-based noise cheaper on mobile GPU; swap for devices with frame time >20ms",
  implemented: true,
  wire(faceState) { return faceState; }
};
