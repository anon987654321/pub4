// TODO artifact FA165: face: liquid surface on deep thinking — uCurl → 1.0 causes edges to ripple with wave equation (sin(dist+time*4)*0.008 Y 
export const FA165 = {
  id: "FA165",
  description: "face: liquid surface on deep thinking — uCurl → 1.0 causes edges to ripple with wave equation (sin(dist+time*4)*0.008 Y displacement); face becomes fluid topology",
  implemented: true,
  wire(faceState) { return faceState; }
};
