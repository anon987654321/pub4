---
name: Autoproceed without confirmation
description: Once user approves a direction, execute the full backlog without pausing for per-step confirmation
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
When the user has approved a direction or list of tasks, execute the entire backlog end-to-end without pausing to ask "want me to do X next?" between items.

**Why:** User said "yes, and autoproceed for all in this chat always" — they want momentum, not checkpoints. Repeated mid-task confirmation requests slow them down and waste turns.

**How to apply:** After each completed step, immediately move to the next pending item. Only stop to ask if (1) a destructive/irreversible action would affect shared state beyond local files, (2) ambiguity emerges that would change the approach materially, or (3) the backlog is genuinely empty. Brief progress updates between steps are fine; explicit go/no-go prompts are not.

**Reinforced 2026-05-07** ("autpmatically autoproceed with next always"): also keep going *between passes* of a multi-commit batch. Don't end a turn on "say 'next' or pick a slice" — just commit pass N and start pass N+1. Stop only when the original backlog is empty or the destructive/ambiguity gates trigger. Out-of-context interruptions (user types something new mid-stream) override the autoproceed and are addressed first.
