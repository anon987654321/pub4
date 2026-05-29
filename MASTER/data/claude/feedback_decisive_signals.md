---
name: Decisive short directives = full authorization
description: Short lowercase replies ("ship all", "kill X keep Y", "yes", "i think X") are binding — execute pass-by-pass without re-confirming.
type: feedback
status: consolidated
canonical: data/principles/feedback_decisive_signals.md
---
**Consolidated.** This content is now maintained as single source in `data/principles/feedback_decisive_signals.md`.

See the principles/ version for the current authoritative text. This file is kept only for historical session traceability.
- "i think X" → user has settled on X, proceed
- "propose N X" → wants a numbered, categorized list with one-liner per item, grouped by surface (type, color, motion, etc.); user then picks a slice or says "ship all"

For large approved batches (>10 items), ship in coherent commit-sized passes (~10–12 items per commit), checkpoint briefly between passes. Don't try to ship 40 in one go. Don't ask "are you sure" or stall on confirmation between passes — checkpoint = one short status sentence, not a question.

**Why:** Validated on 2026-05-07 lofi-aesthetic session. I diagnosed a two-voice TTS bug, user said "kill cli tts, keep web tts" (one sentence, decisive), I executed without re-asking. Then I proposed 40 lofi refinements organized by surface, user said "can we ship all?", I scoped pass-by-pass and started shipping — user then explicitly said "make sure we codify my messages that lead to great success like now."

**How to apply:** Treat one-line approvals as binding contracts. For "ship all N" where N > 10, propose pass plan in 1–2 sentences, execute pass 1, give a one-sentence checkpoint, continue. Stop only on failure, ambiguity, or destructive scope.
