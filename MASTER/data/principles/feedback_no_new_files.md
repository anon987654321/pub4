---
name: no new files without approval
description: Never create new files — always edit originals in place
type: feedback
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---
Always edit the original file directly. Never create intermediate files (local staging files, _fixed.rb copies, tmp patches) without explicit approval.

**Why:** User explicitly said "write changes back into original files don't create new files ever without approval."
**How to apply:** Use Edit tool on the actual file path, or write patch Ruby to /tmp on the VPS and run it in-place — but never create a local copy. The /tmp/patch.rb VPS pattern from DEPLOY/OPERATOR.md is fine since it is a transient runner, not a persisted file.
