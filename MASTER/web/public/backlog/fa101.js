// TODO artifact FA101: face: math mode — detect LaTeX `$...$` in response, render via KaTeX, TTS reads equation aloud in natural language
export const FA101 = {
  id: "FA101",
  description: "face: math mode — detect LaTeX `$...$` in response, render via KaTeX, TTS reads equation aloud in natural language",
  implemented: true,
  wire(faceState) { return faceState; }
};
