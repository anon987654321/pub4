---
name: Mandatory lint/beautify on touch
description: Every file edited must be linted and beautified — not just the target lines
type: feedback
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---
Run lint and beautify on every file you touch, not only changed lines. After Ruby, Zsh, JS, or HTML edits, fix spacing, collapse double blank lines, replace magic literals with constants, and align related assignments when the file already does.

Verify syntax after beautifying. Touching a file obligates a full-file pass, not a narrow patch cleanup.