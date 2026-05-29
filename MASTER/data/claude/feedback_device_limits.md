---
name: No heavy work on device
description: Termux/Android — defer CPU/IO-heavy tasks to VPS, keep device work minimal
type: feedback
status: consolidated
canonical: data/principles/feedback_device_limits.md
---
**Consolidated.** This content is now maintained as single source in `data/principles/feedback_device_limits.md`.

See the principles/ version for the current authoritative text. This file is kept only for historical session traceability.

**Why:** User said "prefer using the VPS" and "avoid doing heavy stuff on this device."

**How to apply:** Default to SSH into the VPS for every task — edits, Ruby runs, git, clones, builds. Only fall back to this device when VPS SSH is down and the task is genuinely lightweight (small curl, quick read).
