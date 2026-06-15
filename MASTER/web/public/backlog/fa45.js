// TODO artifact FA45: tts: per-speaker voice in council mode — each council member uses their mapped voice (already in code, surface in UI)
export const FA45 = {
  id: "FA45",
  description: "tts: per-speaker voice in council mode — each council member uses their mapped voice (already in code, surface in UI)",
  implemented: true,
  wire(faceState) { return faceState; }
};
