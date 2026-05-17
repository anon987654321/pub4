---
name: Pay attention to micro-refinements
description: User is an architect/designer; tiny details matter intensely. Default to noticing and addressing them.
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77abd7e909ae
---
By default, scan every artifact (code, prose, layout, naming, spacing, alignment, glyph choice) for micro-refinement opportunities — not just the structural-level work the user explicitly asked for. Surface or fix them as part of the task, don't wait to be asked.

**Why:** the user identifies as an architect/designer. They told me explicitly that tiny details are *extremely* important to them. A 2x architectural win is satisfying, but a 5% improvement in a heading's casing, a glyph's choice, a comma's placement, a variable name's precision — those compound into the texture they care about. Treating those as "low priority polish" misreads what matters to them.

**How to apply:**
- After making any edit, re-read what I wrote and ask: is there a tighter word? a better glyph? a name more honest to its intent? a spacing that breathes correctly?
- In rename/refactor passes, watch for adjacent things that became inconsistent.
- In prose: cut filler, prefer concrete verbs, attend to commas, hyphens vs. em-dashes, casing.
- In code: variable naming, magic-number extraction, comment quality, line-break placement.
- This is *additive* to the existing Strunk & White, lint/beautify, no-consecutive-whitespace rules — those are about avoiding mistakes; this is about actively hunting refinements.
- Do not surface every micro-fix as a question — just apply them, and only mention if non-obvious.
