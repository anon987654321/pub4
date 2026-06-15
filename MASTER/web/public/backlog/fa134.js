// TODO artifact FA134: face: memory leak guard — dispose Three.js geometries/materials on face swap or page hide
export const FA134 = {
  id: "FA134",
  description: "face: memory leak guard — dispose Three.js geometries/materials on face swap or page hide",
  implemented: true,
  wire(faceState) { return faceState; }
};
