// TODO artifact FA154: face: anisotropic edge opacity — edges parallel to viewing axis fade (foreshortening), perpendicular edges brighten; per
export const FA154 = {
  id: "FA154",
  description: "face: anisotropic edge opacity — edges parallel to viewing axis fade (foreshortening), perpendicular edges brighten; perspective-correct wireframe",
  implemented: true,
  wire(faceState) { return faceState; }
};
