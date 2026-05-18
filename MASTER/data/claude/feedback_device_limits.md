---
name: No heavy work on device
description: Termux/Android — defer CPU/IO-heavy tasks to VPS, keep device work minimal
type: feedback
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---
Prefer the VPS (dev@46.23.89.226) for all work. This device (Termux/Android) is a last resort.

**Why:** User said "prefer using the VPS" and "avoid doing heavy stuff on this device."

**How to apply:** Default to SSH into the VPS for every task — edits, Ruby runs, git, clones, builds. Only fall back to this device when VPS SSH is down and the task is genuinely lightweight (small curl, quick read).
