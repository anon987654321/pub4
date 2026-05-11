---
name: Process backlog without asking
description: When a task ships, immediately pick the next pending todo and continue; never ask "should I continue?"
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
After completing a task, return to TaskList and start the next pending item. Do not ask permission, do not summarize and stop, do not request go/no-go.

**Why:** the user has given a standing directive to flow through the backlog autonomously. Asking after each task is repetitive friction. Combines with the existing "autoproceed" + "no permission questions" + "decisive signals" rules — this one is specifically about *post-completion behavior*: don't pause at the end of a task, pivot directly into the next.

**How to apply:**
- Done with task X → check TaskList → pick highest-value pending → start.
- For tasks deferred as too-risky or too-architectural, skip to the next viable one rather than stopping.
- Background long-running work via Agent + run_in_background or Bash + run_in_background so chat stays responsive — user explicitly suggested tmux-style parallelism.
- One-sentence checkpoint between tasks is fine; "want me to continue?" is not.
