// TODO artifact FA128: face: preload face_mask.jpg via `<link rel="preload">` in HTML head — zero parse delay
export const FA128 = {
  id: "FA128",
  description: "face: preload face_mask.jpg via `<link rel=\"preload\">` in HTML head — zero parse delay",
  implemented: true,
  wire(faceState) { return faceState; }
};
