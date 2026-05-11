---
name: Rules are universal principles, applied cross-disciplinary
description: Every MASTER rule is a medium-agnostic principle with per-medium adapters; design ↔ structure ↔ prose are the same rule
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
Rules in MASTER must be **principles**, not medium-specific checks. The medium (Ruby AST, JSON, YAML, HTML DOM, prose, CSS, layout) is an adapter, not a rule property.

**Why:** user is an architect; cross-disciplinary universality is core to their aesthetic. SMALL_PARTS should apply to methods, YAML maps, prose paragraphs, HTML sections. VERTICAL_RHYTHM applies to typography AND code spacing AND data indentation. NESTING_DEPTH applies to Ruby blocks, JSON objects, divs, subordinate clauses. NAMING_SILHOUETTE applies to identifiers, file names, headings.

**How to apply:**
- Every rule gets a `principle:` field (the universal it embodies) and a `medium:` list (where it applies: `[ruby, yaml, json, html, prose, css]`).
- `detect_structural` handler dispatches on medium → parser → tree-walker; rule logic stays medium-agnostic.
- Design principles (rhythm, contrast, hierarchy, alignment, proximity) become first-class rules applied to AST shape and file silhouette, not just visual layout.
- When adding a new rule, ask: "what other media does this principle apply to?" — if the answer is none, the rule is probably mis-framed.
- Inverse: when adding a rule for a non-code medium (prose, css, yaml), check if the principle already exists for code; reuse it instead of duplicating.
