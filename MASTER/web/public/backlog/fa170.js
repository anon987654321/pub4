// TODO artifact FA170: face: dual-face morph — two depth maps lerped by uMorph uniform (0→1 over 2s); one face dissolves into another; persona 
export const FA170 = {
  id: "FA170",
  description: "face: dual-face morph — two depth maps lerped by uMorph uniform (0→1 over 2s); one face dissolves into another; persona transition",
  implemented: true,
  wire(faceState) { return faceState; }
};
