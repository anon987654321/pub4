---
name: Importance-ordered file layout
description: Every file's lines flow by importance — newspaper inverted pyramid. Most important content at top.
type: feedback
status: consolidated
canonical: data/principles/feedback_importance_order.md
---
**Consolidated.** This content is now maintained as single source in `data/principles/feedback_importance_order.md`.

See the principles/ version for the current authoritative text. This file is kept only for historical session traceability.

**How to apply:**
- Order: requires → module/class declaration + headline doc → public API (ordered by importance/call-frequency) → primary algorithm → private helpers (in dependency order) → constants/tables → edge-case handlers/rescues.
- Applies to ruby, yaml, erb, js, css, html, sh, md — not just Ruby.
- When editing any file, even for a small change, briefly check if the surrounding region needs reordering. Don't rearrange just to rearrange — but if the file is already inverted (helpers at top, public API at bottom), fix it as part of the touch.
- The Maintainer and Layperson council personas evaluate this. Sweep enforces via `IMPORTANCE_ORDER` and `RECOMMENT`.
