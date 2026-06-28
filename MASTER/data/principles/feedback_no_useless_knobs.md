---
name: No useless metrics, thresholds, or categorizations
description: Eliminate knobs whose only effect is "do less / do worse" — defaults should be maximal correctness; lower-effort modes need real justification
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
Don't add knobs whose only effect is "do less" or "do worse" — defaults should be maximal correctness. Kill shallow/standard/deep tiers when everyone picks max; keep tiers only for real tradeoffs (LLM cost, unbounded dump risk). Detection criteria (file >300 lines) stay; effort knobs (scan first 100 files) die. New features ship one right mode; add levels only when a real tradeoff emerges.