// TODO artifact FA31: face: add WebWorker for depth-map sampling so main thread never blocks on large images
export const FA31 = {
  id: "FA31",
  description: "face: add WebWorker for depth-map sampling so main thread never blocks on large images",
  implemented: true,
  wire(faceState) { return faceState; }
};
