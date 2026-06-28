---
name: Proper casing, no ASCII decorations
description: Sentence case in prose, comments, CLI, commit messages; no banner lines, bracket tags, or decorative bullets
type: feedback
applies_to: "prose, comments, CLI output, commit messages, log lines, section headers"
---
Use sentence case in prose, comments, logs, CLI output, and commit messages; keep snake_case for identifiers and capitalize commit subjects. Ban equals-sign banners, bracket tags such as ok or err, and decorative bullets—use ok: and warn: prefixes with hyphen-prefixed items instead.

Dmesg may use lowercase only on MASTER kernel output, not in operator chat. This rule applies to prose, comments, CLI output, commit messages, log lines, and section headers.