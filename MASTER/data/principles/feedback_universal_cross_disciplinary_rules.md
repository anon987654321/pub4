---
name: Rules are universal principles, applied cross-disciplinary
description: Every MASTER rule is a medium-agnostic principle with per-medium adapters; design ↔ structure ↔ prose are the same rule
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
MASTER rules are principles, not medium-specific checks. Medium (Ruby AST, JSON, YAML, HTML, prose, CSS) is an adapter. Each rule gets `principle:` (universal) and `medium:` list. `detect_structural` dispatches parser → tree-walker; logic stays agnostic. SMALL_PARTS, VERTICAL_RHYTHM, NESTING_DEPTH, NAMING_SILHOUETTE span code and design. New rules: ask what other media apply; reuse existing principles instead of duplicating.