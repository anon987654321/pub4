---
name: Diverged branch sync via cherry-pick onto remote
description: When local and remote main have diverged with overlap, cherry-pick the targeted commits onto remote tip rather than rebase mixed history or force-push
type: feedback
status: consolidated
canonical: data/principles/feedback_diverged_branch_sync.md
---
**Consolidated.** This content is now maintained as single source in `data/principles/feedback_diverged_branch_sync.md`.

See the principles/ version for the current authoritative text. This file is kept only for historical session traceability.
4. Resolve conflicts case by case
5. Push

**Why:** User said "push sync github" after a session that produced 16 lofi commits on top of 9 older local commits, while remote had 20 unrelated commits. Rebasing all 25 would have replayed work already on remote in equivalent form, producing duplicate commits and unnecessary conflicts. Force-push would have destroyed the 20 remote commits — unacceptable. The cherry-pick-onto-remote approach shipped exactly the intended work, kept history linear, and was accepted without pushback ("great." after sync).

**How to apply:** Use this when (a) the user's intent is clearly "ship my recent work, not all local work" — e.g. after a focused session like a feature batch, and (b) older local-only commits look duplicated on remote (same area, similar messages). Always create a backup tag before reset. If the user's intent is "preserve all local work", do a full rebase or merge instead.
