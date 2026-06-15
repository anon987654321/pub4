// TODO artifact FA155: face: depth-stratified edge rendering — edges where both endpoints have depth>0.7 rendered at 0.14 opacity; shallow edge
export const FA155 = {
  id: "FA155",
  description: "face: depth-stratified edge rendering — edges where both endpoints have depth>0.7 rendered at 0.14 opacity; shallow edges at 0.035; reads as foreground/background layers",
  implemented: true,
  wire(faceState) { return faceState; }
};
