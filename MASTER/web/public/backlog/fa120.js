// TODO artifact FA120: face: laughter detection — if response contains "(ha" or emoji, particles do a quick jitter burst
export const FA120 = {
  id: "FA120",
  description: "face: laughter detection — if response contains \"(ha\" or emoji, particles do a quick jitter burst",
  implemented: true,
  wire(faceState) { return faceState; }
};
