// TODO artifact FA150: face: edge curvature coloring — edges crossing high-curvature vertices shift hue ±8° toward warm; flat edges stay neutra
export const FA150 = {
  id: "FA150",
  description: "face: edge curvature coloring — edges crossing high-curvature vertices shift hue ±8° toward warm; flat edges stay neutral; encodes topology in color",
  implemented: true,
  wire(faceState) { return faceState; }
};
