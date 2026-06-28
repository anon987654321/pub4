---
name: Reassess comments on every touch
description: Every edit re-reads each comment in the file — delete if obvious, rewrite Strunk & White style if kept.
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
Touching a file means reassessing every comment in it, not only nearby lines. Delete what-comments, code restatements, banners, and YARD blocks. Keep only non-obvious WHY—one line, active voice, concrete verbs.

Do not add comments to new code unless WHY is hidden. Encoded in style.yml comments.reassess_on_touch and patterns.yml RECOMMENT.