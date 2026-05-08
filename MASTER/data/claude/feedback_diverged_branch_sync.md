---
name: Diverged branch sync via cherry-pick onto remote
description: When local and remote main have diverged with overlap, cherry-pick the targeted commits onto remote tip rather than rebase mixed history or force-push
type: feedback
originSessionId: b02ce9b9-a7c7-4c65-b8d0-3b8469dc2028
---
When `git push` is rejected because remote has new commits and local also has commits the remote doesn't, prefer this flow:
1. `git tag backup-pre-sync-YYYY-MM-DD` on local main
2. `git reset --hard origin/main` (backup tag preserves the prior tip)
3. Cherry-pick only the commits we actually want to ship (e.g. session's lofi passes), not the mixed pile of older local-only commits that may already exist upstream in equivalent form
4. Resolve conflicts case by case
5. Push

**Why:** User said "push sync github" after a session that produced 16 lofi commits on top of 9 older local commits, while remote had 20 unrelated commits. Rebasing all 25 would have replayed work already on remote in equivalent form, producing duplicate commits and unnecessary conflicts. Force-push would have destroyed the 20 remote commits — unacceptable. The cherry-pick-onto-remote approach shipped exactly the intended work, kept history linear, and was accepted without pushback ("great." after sync).

**How to apply:** Use this when (a) the user's intent is clearly "ship my recent work, not all local work" — e.g. after a focused session like a feature batch, and (b) older local-only commits look duplicated on remote (same area, similar messages). Always create a backup tag before reset. If the user's intent is "preserve all local work", do a full rebase or merge instead.
