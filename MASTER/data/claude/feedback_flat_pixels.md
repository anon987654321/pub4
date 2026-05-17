---
name: Flat UI, flat pixels except 3D-resemblance
description: Keep all UI and particle rendering flat 2D — uniform size/alpha/no depth illusion — except when pixels arrange to resemble a 3D model (face mode, future 3D model approximations)
type: feedback
originSessionId: 285acce4-505e-4b41-82ff-f88e72ee1535
---
UI is flat. Pixels are flat. No fake depth (z-scaled size, alpha tiers, parallax, motion blur, drop shadows, gradients). The ONLY exception: when pixels collectively arrange themselves to resemble a 3D model — e.g., face mode where fibonacci-sphere anchors project a head shape. In that case the 3D-ness comes from the arrangement, not from per-pixel depth tricks.

**Why:** Aesthetic is 8-bit/dmesg/openbsd — flatness is the brand. Per-particle z-scaling creates a generic "particle.js" look. The face/3D modes earn their depth by being the shape itself, not by faking it everywhere.

**How to apply:**
- Idle particle render: same size (1px), same alpha for all particles
- No motion-blur trail fade — clear background solid each frame
- Tilt parallax IS welcome (gyro/device orientation moves layers at different speeds) — counts as mobile enhancement, not a fake depth shadow
- Orbital cursor: pan force can be uniform, no z-multiplier
- Keep z field for 3D arrangements (face mode) and parallax-style motion only
- CSS: no shadows, gradients, glows, blurs, animated scales — flat fills, hard edges, pixel borders only
