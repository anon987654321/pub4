---
name: Diverged branch sync via cherry-pick onto remote
description: When local and remote main have diverged with overlap, cherry-pick the targeted commits onto remote tip rather than rebase mixed history or force-push
type: feedback
originSessionId: b02ce9b9-a7c7-4c65-b8d0-3b8469dc2028
---
Push rejected with diverged overlap: tag `backup-pre-sync-YYYY-MM-DD`, `reset --hard origin/main`, cherry-pick commits to ship, resolve, push. Cherry-pick when shipping recent session work with dupes on remote; rebase/merge to keep all local work. Never force-push; backup-tag first.