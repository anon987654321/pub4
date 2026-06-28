---
name: tail
description: Read recent event history with a small, focused window.
triggers:
  - "\\btail\\b"
---

The tail skill reads recent event history through a small, focused window so the operator can see what MASTER or the environment did last. It is triggered on tail or when context from the latest log lines would explain the current state.

Show only enough history to explain the current issue or next step. Truncate older noise and highlight timestamps, errors, and the final outcome.