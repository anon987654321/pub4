---
name: Strunk & White style
description: All code output — commits, comments, log messages, CLI output — must follow Strunk & White principles
type: feedback
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---
Apply Strunk & White to every written artifact: commits, comments, log messages, CLI prompts, error messages.

**Why:** User mandate for all text output from and about MASTER.

**How to apply:**
- Active voice: "Fix bug" not "Bug was fixed"
- Omit needless words: "extract Search module" not "perform extraction of Search module functionality"
- Concrete nouns and verbs: "scan", "fix", "load", "route" — not "process", "handle", "manage"
- One idea per sentence
- Commit messages: imperative mood, ≤72 chars, no trailing period
- Comments: state the WHY only, not the WHAT — one line max
- dmesg log lines: `component: action key=val key=val` (no commas, no padding)
