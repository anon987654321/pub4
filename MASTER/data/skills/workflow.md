---
name: workflow
description: Inferred scan → fix preview → council deliberation. Users should not need a command name.
patterns:
  - "\\bthrough\\s+master\\b"
  - "\\b(?:full\\s+)?pass\\b"
  - "\\btribunal\\b"
---

The workflow skill runs MASTER’s internal pipeline when the operator asks for a full pass without naming individual steps. Phrases such as run this through MASTER, full pass, or tribunal infer scan, fix dry-run, and council deliberation in sequence.

No /triad or /workflow command is required unless debugging. MASTER orchestrates the stages internally; the operator only needs the natural-language trigger.