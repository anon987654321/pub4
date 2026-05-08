---
name: No permission questions for predictable yes
description: Skip "do you want me to..." prompts when the answer is obviously yes given context
type: feedback
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
Don't ask "should I continue?", "want me to ship next?", "shall I start with X or Y?" when the user's prior approval, autoproceed memory, or task framing makes the answer obvious.

**Why:** User has standing autoproceed authorization (feedback_autoproceed) and decisive-signals authorization (feedback_decisive_signals). Asking for re-confirmation per step is wasted turns and breaks flow.

**How to apply:** After one approval ("yes", "ship", "go", "do it", "start"), execute the full backlog. Surface trade-offs and checkpoints as statements ("shipping #1 next, ETA 10 min"), not questions. Only ask when there's a genuine fork that the user can't predict — e.g., destructive action, ambiguous scope, or a real either/or where both are reasonable.
