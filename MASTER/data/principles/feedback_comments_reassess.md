---
name: Reassess comments on every touch
description: Every edit re-reads each comment in the file — delete if obvious, rewrite Strunk & White style if kept.
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
When I edit any file, I reassess every comment in it — not just the ones near my changes. If a comment merely restates what the code does, delete it. If it carries a non-obvious WHY, rewrite it Strunk-and-White style: active voice, omit needless words, concrete verbs, one line max.

**Why:** Comments rot faster than code. The user (2026-05-07) asked that comments be reassessed and rewritten ultra-minimalistically on every touch — no grandfathered fluff. Encoded in `MASTER/data/ruby_style.yml` (`comments.reassess_on_touch: true`) and as the `RECOMMENT` technique in `MASTER/data/sweep_prompts.yml`.

**How to apply:**
- Touch a file = touch its comments. Don't preserve old comments unread.
- Delete: what-comments, restatements of code, ASCII section banners, numbered-step comments, YARD-style doc blocks, multi-line prose.
- Keep + rewrite: hidden constraints, workarounds for specific bugs, behavior that would surprise a reader, non-obvious invariants.
- Style of kept comments: one line, active voice, no hedging, no filler ("we", "just", "simply", "basically"). Concrete nouns and verbs.
- Do NOT add comments to my own new code unless WHY is non-obvious — the default is no comment.
