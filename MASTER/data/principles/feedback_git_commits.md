---
name: frequent git commits
description: Make git commits frequently after meaningful changes
type: feedback
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---
Commit after every meaningful change — don't batch. After fixing a bug, restoring a file, or completing a refactor, commit immediately.

**Why:** User explicitly requested frequent commits.
**How to apply:** After any file write or fix on the VPS, run `git add <file> && git commit -m "..."` before moving on.
