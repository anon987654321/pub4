// TODO artifact FA157: face: vertex size by valence — vertices with 6 neighbors (interior) at base size; 3-4 neighbor vertices (boundary) at 1.
export const FA157 = {
  id: "FA157",
  description: "face: vertex size by valence — vertices with 6 neighbors (interior) at base size; 3-4 neighbor vertices (boundary) at 1.5× to accent silhouette",
  implemented: true,
  wire(faceState) { return faceState; }
};
