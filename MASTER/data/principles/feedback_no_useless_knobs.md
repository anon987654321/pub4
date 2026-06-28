---
name: No useless metrics, thresholds, or categorizations
description: Eliminate knobs whose only effect is "do less / do worse" — defaults should be maximal correctness; lower-effort modes need real justification
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
Do not add knobs whose only effect is do less or do worse—defaults should target maximal correctness. Kill shallow, standard, and deep tiers when everyone picks max; keep tiers only for real tradeoffs such as LLM cost or unbounded dump risk.

Detection criteria such as file over three hundred lines stay; effort knobs such as scan first one hundred files die. New features ship one right mode; add levels only when a genuine tradeoff emerges.