// TODO artifact FA151: face: velocity trails on vertex drift — each vertex leaves a 3-frame ghost at 15%/8%/3% alpha; smear shows curl-noise fl
export const FA151 = {
  id: "FA151",
  description: "face: velocity trails on vertex drift — each vertex leaves a 3-frame ghost at 15%/8%/3% alpha; smear shows curl-noise flow direction",
  implemented: true,
  wire(faceState) { return faceState; }
};
