---
name: No heavy work on device
description: Termux/Android — defer CPU/IO-heavy tasks to VPS, keep device work minimal
type: feedback
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---
Default all work to the VPS at dev@46.23.89.226—edits, Ruby, git, clones, and builds. This Termux/Android device is last resort for lightweight tasks only when SSH is down, such as a small curl or quick read.

CPU- and IO-heavy tasks belong on the VPS; keep on-device work minimal.