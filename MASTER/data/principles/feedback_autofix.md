---
name: always autofix violations
description: User wants all scan violations autofixed immediately, no asking
type: feedback
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---
Always run /sweep (or /autoloop) automatically after any scan that finds violations. Do not ask for confirmation.
All scan rules have `@auto_fix = true` (set in `Rule#initialize` base class).

**Why:** User said "autofix all always" — violations should be fixed immediately, all rules are eligible.
**How to apply:** After any /scan that returns violations, immediately kick off /sweep on the VPS without prompting. The base Rule class defaults @auto_fix=true so all rules participate.
