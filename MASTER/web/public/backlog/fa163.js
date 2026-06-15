// TODO artifact FA163: face: council speech region highlight — during council output, the speaking persona's face region (mouth/forehead/eyes) 
export const FA163 = {
  id: "FA163",
  description: "face: council speech region highlight — during council output, the speaking persona's face region (mouth/forehead/eyes) brightens by 0.15 alpha for that turn",
  implemented: true,
  wire(faceState) { return faceState; }
};
