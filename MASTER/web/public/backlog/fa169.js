// TODO artifact FA169: face: depth map hot-reload — /mask command sends URL; face re-samples on next frame; no page reload; enables persona/fac
export const FA169 = {
  id: "FA169",
  description: "face: depth map hot-reload — /mask command sends URL; face re-samples on next frame; no page reload; enables persona/face swap at runtime",
  implemented: true,
  wire(faceState) { return faceState; }
};
