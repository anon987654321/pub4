// shared_palette.js — 8-bit palette (256 colors) shared across orb views
// 
// Usage: Include this script in HTML files before any script that uses palette:
//   <script src="shared_palette.js"></script>
//
// Exports:
//   - PAL: Array of 256 RGB color triplets [r,g,b]
//   - quantize(r,g,b): Returns closest palette color to given RGB values
//
// The 256-color palette consists of:
//   - 252 colors: 6×7×6 RGB cube (r∈{0,51,102,153,204,255}, g∈{0,42,84,126,168,210,252}, b∈{0,51,102,153,204,255})
//   - 4 grayscale: [0,0,0], [85,85,85], [170,170,170], [255,255,255]
//   Total: 252 + 4 = 256 colors

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
