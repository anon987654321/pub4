---
name: fix
description: Apply targeted repairs and verify the result.
triggers:
  - "\\bfix\\b"
---

The fix skill applies targeted repairs and verifies that the change actually resolves the reported problem. It activates on fix or when MASTER is asked to repair a specific defect rather than redesign a subsystem.

Prefer minimal edits, preserve user work, and verify the change path end to end. Confirm behavior with tests, logs, or a reproducible check before treating the fix as complete.