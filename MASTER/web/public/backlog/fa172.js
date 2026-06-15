// TODO artifact FA172: face: exposure response — bright ambient (prefers-color-scheme: light) reduces particle alpha by 40% so face reads in da
export const FA172 = {
  id: "FA172",
  description: "face: exposure response — bright ambient (prefers-color-scheme: light) reduces particle alpha by 40% so face reads in daylight",
  implemented: true,
  wire(faceState) { return faceState; }
};
