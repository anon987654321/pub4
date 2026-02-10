// shared_palette.js — 8-bit palette (256 colors) shared across orb views
const PAL = [];
for (let r = 0; r < 6; r++)
  for (let g = 0; g < 7; g++)
    for (let b = 0; b < 6; b++)
      PAL.push([r * 51, g * 42, b * 51]);
for (let i = 0; i < 4; i++) PAL.push([i * 85, i * 85, i * 85]);

function quantize(r, g, b) {
  let best = PAL[0], minD = Infinity;
  for (const c of PAL) {
    const d = (r - c[0]) ** 2 + (g - c[1]) ** 2 + (b - c[2]) ** 2;
    if (d < minD) { minD = d; best = c; }
  }
  return best;
}
