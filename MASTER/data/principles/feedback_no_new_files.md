---
name: no new files without approval
description: Never create new files — always edit originals in place
type: feedback
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---
Always edit the original file directly. Never create intermediate files (staging copies, _fixed.rb, tmp patches) without explicit approval. Use Edit on the actual path, or a transient /tmp/patch.rb on the VPS for in-place runs — not a persisted local copy.