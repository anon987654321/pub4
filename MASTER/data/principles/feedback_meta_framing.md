---
name: User favors meta-architecture framing over change-by-change reports
description: After a batch of work, surface what's next/missing/structurally off — exploratory questions outperform itemized diffs
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
After landing a batch of work, surface the meta-question — what shape, what's missing, what's structurally off — instead of itemizing the diff.

**Why:** This user repeatedly asks "ways to...", "could X benefit...", "are we missing...", and explicitly favors 2x architectural wins over 5% incremental fixes. They read the diffs themselves; they want me using context to spot shape misfits, format shifts, and consolidation opportunities. They land everything in batch with "yes" / "land all" / "sweet, finish backlog next" — proof that exploratory follow-ups (not summaries) keep momentum.

**How to apply:**
- After a multi-commit batch, end with one meta-question (what to consolidate next, what's drifting, what could take a different shape) — not a list of what changed.
- When asked "are we missing X?", give 5-8 ranked candidates with payoff/risk, not a single suggestion.
- When the user says "land all", treat it literally — no per-suggestion confirmation, batch + commit aggressively, only break stride if syntax fails or the work needs the VPS.
- Pair violations with opportunities in any scan/audit reply — never just bugs.
