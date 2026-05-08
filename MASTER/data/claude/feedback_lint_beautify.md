---
name: Mandatory lint/beautify on touch
description: Every file edited must be linted and beautified — not just the target lines
type: feedback
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---
Run a lint/beautify pass on every file you touch, not just the specific lines changed.

**Why:** User instruction: "mandatory lint / beautify of everything it touches"

**How to apply:** After any edit to a Ruby/Zsh/JS/HTML file, apply style fixes to the whole file: consistent spacing around operators, no double blank lines, use defined constants instead of magic literals, align related assignments if the file already does so. Verify syntax after.
