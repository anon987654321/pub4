// TODO artifact FA158: face: diagonal edge suppression — render only right+below edges at rest; diagonal edges fade in during thinking state; d
export const FA158 = {
  id: "FA158",
  description: "face: diagonal edge suppression — render only right+below edges at rest; diagonal edges fade in during thinking state; density doubles without geometry change",
  implemented: true,
  wire(faceState) { return faceState; }
};
