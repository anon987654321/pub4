---
name: No multiple consecutive whitespace anywhere
description: Single space, single blank line max, no trailing whitespace — across Ruby, JS, CSS, HTML, YAML, shell, Markdown.
type: feedback
originSessionId: b02ce9b9-a7c7-4c65-b8d0-3b8469dc2028
---
Multiple consecutive whitespace is forbidden across all file types. Applies to:

- Two or more spaces in a row mid-line — one space only (no aligned-column padding like `@foo   = 1`)
- Two or more blank lines in a row — single blank line max between sections
- Trailing whitespace at line end
- Indentation beyond level (no double-indent for visual alignment)

**Why:** Stated by user 2026-05-07 during lofi pass 1 session. Tightens "ultra-minimalistic coding style" and the Strunk & White principle: omit needless characters, not just needless words. Aligned-column padding is filler.

**How to apply:** When editing a file, collapse runs of spaces and blank lines as part of the lint/beautify-on-touch pass. When writing new code, never align `=` or values with extra spaces; never leave two blank lines between methods. CSS one-liners fine; CSS multi-line fine; tabular alignment via spaces not fine.
