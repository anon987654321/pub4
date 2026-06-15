// TODO artifact FA173: face: WebGL instanced mesh — replace Points+LineSegments with InstancedMesh for nodes; 2× draw-call reduction; same visu
export const FA173 = {
  id: "FA173",
  description: "face: WebGL instanced mesh — replace Points+LineSegments with InstancedMesh for nodes; 2× draw-call reduction; same visual, lower GPU overhead",
  implemented: true,
  wire(faceState) { return faceState; }
};
