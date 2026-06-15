// TODO artifact FA30: face: ambient occlusion fake — particles at mask dark-pixel regions get alpha 0.12, bright get 0.35
export const FA30 = {
  id: "FA30",
  description: "face: ambient occlusion fake — particles at mask dark-pixel regions get alpha 0.12, bright get 0.35",
  implemented: true,
  wire(faceState) { return faceState; }
};
