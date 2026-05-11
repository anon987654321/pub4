---
name: Auto-update README.md when needed
description: After any meaningful change to MASTER's behavior or capabilities, update README.md without prompting
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
When a commit changes MASTER's user-facing behavior, capabilities, command surface, philosophy, or stack, update README.md in the same or a follow-up commit without waiting for the user to ask.

**Why:** Stated explicitly on 2026-05-05. README is the single front door — drift between it and the code degrades trust. The user prefers the doc to lead, not lag.

**How to apply:**
- After landing depth flips, rule additions, workflow changes, persona changes, scan/sweep semantics changes, model routing changes, or any new top-level concept (Six Laws, biases, structural_ops, etc.) — refresh the matching README paragraph.
- Refresh = update the prose, not append a changelog entry. Keep README's flowing-prose / Strunk & White / Bringhurst form (no h2/h3, no tables, no code blocks unless essential).
- Bundle the doc update with the code commit when small; split into a follow-up if the doc change is substantial.
- Skip auto-update only for trivial bugfixes that don't change observable behavior.
