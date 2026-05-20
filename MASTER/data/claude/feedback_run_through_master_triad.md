---
name: "Run X through MASTER" = scan + sweep + council
description: User shorthand — "run X through master" means scan + sweep + council/tribunal (called "council" in code, "tribunal" in user vocabulary), not just /scan
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
When the user says "run X through MASTER" (or "expose X to MASTER", "MASTER on X"), run the chain: `/scan <path>` → `/sweep <path>` to convergence → `/council <path>`. Council = deliberation pass with the 6 personas and Security veto.

Why: User confirmed "yeah when user says run this or that through master, then a triad is what i expect" → "/scan+sweep+tribunal" (2026-05-08). User uses "tribunal", code uses "council" — same thing. The `/triad` wrapper was removed in commit 7670306c per the rule that the user should never need to know a command name.

How to apply: For any directive "run/scan/process X through master" where X is a path or codebase, run the three commands in sequence. Don't ask which depth — scan is deep by default.
