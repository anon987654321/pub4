// TODO artifact FA34: face: chromatic aberration on flash state — R channel offset +1px, B offset -1px for 200ms
export const FA34 = {
  id: "FA34",
  description: "face: chromatic aberration on flash state — R channel offset +1px, B offset -1px for 200ms",
  implemented: true,
  wire(faceState) { return faceState; }
};
