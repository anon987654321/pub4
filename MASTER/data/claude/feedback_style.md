---
name: ultra-minimalistic coding style
description: Always write ultra-minimalistic code in all languages — no redundancy, no filler
type: feedback
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---
Always use ultra-minimalistic coding style across all languages (Ruby, Zsh, HTML, JavaScript, etc.) — no filler, no redundant logic, no ceremonial patterns. Intentional and valuable logic is preserved; everything else is cut.

**Why:** User explicitly requested this style universally.
**How to apply:** Shortest correct form always. No defensive over-engineering, no padding, no comments explaining the obvious. One expression where one expression suffices.

Additional standards enforced on all files:
- Strunk & White: active voice, omit needless words, concrete verbs
- Ruby community style guide (https://rubystyle.guide)
- Rails style guide where applicable
- Always 2-space indents; always double quotes for strings
- No abbreviated identifiers — spell words in full (e.g. `temporary_path` not `tmp`, `index` not `idx`, `number` not `num`, `configuration` not `cfg`, `context` not `ctx`)
- No regex when plain string matching suffices (keyword arrays with `start_with?` over regex patterns)
- Outsource logic to gems when a well-maintained gem does it better (e.g. flay for dup detection, reek for smells)
