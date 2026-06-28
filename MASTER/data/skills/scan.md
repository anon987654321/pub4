---
name: scan
description: Scan files or directories for violations and opportunities.
triggers:
  - "\\bscan\\b"
---

The scan skill searches files or directories for violations, smells, and improvement opportunities within the requested scope. It is triggered on scan or as the first step of broader MASTER workflows that need evidence before fix or deliberation.

Findings should be evidence-led and narrow to the requested target. Report path, line or pattern, and severity so downstream skills can act without re-scanning the whole tree.