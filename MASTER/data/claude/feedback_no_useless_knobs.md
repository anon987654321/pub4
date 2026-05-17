---
name: No useless metrics, thresholds, or categorizations
description: Eliminate knobs whose only effect is "do less / do worse" — defaults should be maximal correctness; lower-effort modes need real justification
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77abd7e909ae
---
Don't add a knob whose only effect is "do less" or "do worse." Defaults should be maximal correctness.

Example: `/scan shallow` vs `/scan standard` vs `/scan deep` — there's no situation where the user wants an *incomplete* scan, so the categorization is dead weight. Just `/scan` always does the thorough thing.

**Why:** every knob is a question the user has to answer, and most "lite/fast/shallow" modes exist because the implementation was once slow — not because anyone actually wants the degraded output. Knobs accrete; defaults rarely catch up. The user wants the right answer, not a menu of wrong ones.

**How to apply:**
- Audit every CLI flag, depth/limit param, and named tier (shallow/standard/deep, light/full, basic/advanced) — if every user always picks the maximum, kill the lower tiers and make max the default.
- Keep the knob only when there's a *real* tradeoff the user genuinely makes (cost-tier lexical/structural/semantic = real, because LLM is expensive; depth=2 vs unbounded if unbounded would dump GBs = real).
- Don't confuse **detection criteria** (file >300 lines = violation) with **effort knobs** (scan only the first 100 files) — criteria stay, effort knobs die.
- Token bars, budget caps, max_lines, max_depth: each one needs a real reason. If the only reason is "we used to be slow," cut it.
- Inverse rule: when adding a new feature, don't preemptively add levels/modes. Ship one mode (the right one). Add levels later only if a real tradeoff emerges.
