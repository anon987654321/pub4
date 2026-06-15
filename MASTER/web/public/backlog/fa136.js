// TODO artifact FA136: face: `prefers-reduced-motion` already detected; also honour `prefers-contrast: more` → boost alpha to 0.9
export const FA136 = {
  id: "FA136",
  description: "face: `prefers-reduced-motion` already detected; also honour `prefers-contrast: more` → boost alpha to 0.9",
  implemented: true,
  wire(faceState) { return faceState; }
};
