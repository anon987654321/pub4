// FA backlog registry — wires face UI backlog items at load time.
import * as stubs from './registry.js';

export function wireFaceBacklog(faceState = {}) {
  const wired = Object.values(stubs).filter((item) => item?.implemented);
  wired.forEach((item) => {
    if (typeof item.wire === 'function') item.wire(faceState);
  });
  return { count: wired.length, faceState };
}