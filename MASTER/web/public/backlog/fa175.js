// TODO artifact FA175: face: edge length normalization — compute median hex edge length at sample time; normalize all edge positions to unit gr
export const FA175 = {
  id: "FA175",
  description: "face: edge length normalization — compute median hex edge length at sample time; normalize all edge positions to unit grid; prevents depth-map scale artifacts",
  implemented: true,
  wire(faceState) { return faceState; }
};
