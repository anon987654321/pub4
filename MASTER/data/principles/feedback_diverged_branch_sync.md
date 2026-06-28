---
name: Diverged branch sync via cherry-pick onto remote
description: When local and remote main have diverged with overlap, cherry-pick the targeted commits onto remote tip rather than rebase mixed history or force-push
type: feedback
originSessionId: b02ce9b9-a7c7-4c65-b8d0-3b8469dc2028
---
When push is rejected because local and remote main have diverged with overlapping commits, tag backup-pre-sync-YYYY-MM-DD, reset hard to origin/main, cherry-pick the commits you intend to ship, resolve conflicts, and push.

Cherry-pick when shipping recent session work that duplicates commits already on remote; rebase or merge when you need all local work preserved. Never force-push; create the backup tag first.