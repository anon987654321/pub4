---
name: "Run X through MASTER" = scan + sweep + tribunal
description: User shorthand — "run X through master" means /triad = scan + sweep + tribunal (called "council" in code, "tribunal" in user vocabulary), not just /scan
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
When the user says "run X through MASTER" (or "expose X to MASTER", "MASTER on X"), default to /triad — scan, sweep to convergence, then tribunal deliberation. Tribunal = the council deliberation pass with the 6 personas and Security veto.

Why: User confirmed "yeah when user says run this or that through master, then a triad is what i expect" → "/scan+sweep+tribunal" (2026-05-08). User uses "tribunal", code uses "council" — same thing.

How to apply: For any directive "run/scan/process X through master" where X is a path or codebase, invoke `/triad deep <path>`. Bug to flag: current /triad's third step calls the council META command (just on/off toggle) instead of running an actual deliberation.review — surface this when relevant.
