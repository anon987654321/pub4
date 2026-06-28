---
name: resync
description: Reconcile the worktree or runtime state with the intended source of truth.
triggers:
  - "\\bresync\\b"
---

The resync skill reconciles the worktree or runtime state with the intended source of truth after drift, failed merges, or stale caches. It is triggered on resync or when MASTER must realign local state with git, config, or an external canonical copy.

Use after divergence, and confirm the restored state with evidence before moving on. Show what was out of sync, what was reset or merged, and how the result was verified.