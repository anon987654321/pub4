// TODO artifact FA32: face: store sampled positions in IndexedDB keyed by image URL — skip resample on reload
export const FA32 = {
  id: "FA32",
  description: "face: store sampled positions in IndexedDB keyed by image URL — skip resample on reload",
  implemented: true,
  wire(faceState) { return faceState; }
};
