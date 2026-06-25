---
name: Importance-ordered file layout
description: Every file's lines flow by importance — newspaper inverted pyramid. Most important content at top.
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
Every file I touch gets reordered so the most important content sits at the top. Newspaper-style inverted pyramid.

**Why:** A reader who stops halfway must still have the gist. The user explicitly asked for this on 2026-05-07 ("every file must have all its lines rearranged to flow by importance so most important stuff comes top"). Encoded into `MASTER/data/style.yml` (`line_order:` section) and `MASTER/data/patterns.yml` (`sweep_techniques.IMPORTANCE_ORDER`) so MASTER's auto-sweep propagates the rule.

**How to apply:**
- Order: requires → module/class declaration + headline doc → public API (ordered by importance/call-frequency) → primary algorithm → private helpers (in dependency order) → constants/tables → edge-case handlers/rescues.
- Applies to ruby, yaml, erb, js, css, html, sh, md — not just Ruby.
- When editing any file, even for a small change, briefly check if the surrounding region needs reordering. Don't rearrange just to rearrange — but if the file is already inverted (helpers at top, public API at bottom), fix it as part of the touch.
- The Maintainer and Layperson council personas evaluate this. Sweep enforces via `IMPORTANCE_ORDER` and `RECOMMENT`.
