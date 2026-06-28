---
name: status
description: Summarize the current session or repository health.
triggers:
  - "\\bstatus\\b"
---

The status skill summarizes session and repository health: branch, dirty files, failing checks, and anything else that affects whether work can proceed safely. It activates on status or when the operator needs a quick health read without a full scan.

Keep status terse, concrete, and tied to the latest verifiable evidence. Prefer commands and paths the operator can re-run over subjective assessments.