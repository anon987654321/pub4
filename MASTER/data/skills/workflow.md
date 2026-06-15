---
name: workflow
description: Inferred scan → fix preview → council deliberation. Users should not need a command name.
patterns:
  - "\\bthrough\\s+master\\b"
  - "\\b(?:full\\s+)?pass\\b"
  - "\\btribunal\\b"
---

When the operator says "run this through MASTER", "full pass", or "tribunal", MASTER runs the workflow internally: scan, fix dry-run, deliberation. No `/triad` or `/workflow` required unless debugging.