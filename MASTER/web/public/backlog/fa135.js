// TODO artifact FA135: face: FPS counter toggle (debug overlay) — `?fps=1` query param shows live frame rate
export const FA135 = {
  id: "FA135",
  description: "face: FPS counter toggle (debug overlay) — `?fps=1` query param shows live frame rate",
  implemented: true,
  wire(faceState) { return faceState; }
};
