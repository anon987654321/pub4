---
name: always autofix violations
description: User wants all scan violations autofixed immediately, no asking
type: feedback
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---
After any `/scan` that finds violations, immediately run `/sweep` (or `/autoloop`) on the VPS without asking. All rules default `@auto_fix = true` in `Rule#initialize` — every rule participates.