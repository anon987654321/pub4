---
name: ecology
description: Inspect the repository ecology and connected file relationships.
triggers:
  - "\\becology\\b"
---

The ecology skill inspects how files, modules, and dependencies relate across the repository. It is triggered when the operator mentions ecology or when MASTER needs a grounded map of connected artifacts rather than an isolated file view.

Favor direct file and graph evidence over abstract summaries. Name concrete paths, imports, and call sites so follow-up work can start from evidence instead of inference.