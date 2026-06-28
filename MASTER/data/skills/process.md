---
name: process
description: Summarize the current operating state of MASTER.
triggers:
  - "\\bprocess\\b"
---

The process skill summarizes MASTER’s current operating state: what is running, what stage a workflow is in, and which subsystems are active. It is triggered on process or when the operator needs a snapshot of runtime behavior rather than repository contents.

Keep operational output compact enough to scan in one glance. Lead with the facts that unblock the next action and omit narrative filler.