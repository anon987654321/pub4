---
name: Proper casing, no ASCII decorations
description: Sentence case in prose, comments, CLI, commit messages; no ===, originSessionId: b02ce9b9-a7c7-4c65-b8d0-3b8469dc2028
---
-, [ok], •, |, › as ASCII art.
type: feedback
applies_to: prose, comments, CLI output, commit messages, log lines, section headers
---

Use proper casing in prose, comments, log lines, CLI output, and commit messages. Capitalize sentence starts, proper nouns, and acronyms. Snake_case identifiers stay as-is.

Commit messages: capitalize the first word of the subject line. `Kill cli tts; web is sole audio path` not `kill cli tts; web is sole audio path`. Body paragraphs follow normal sentence-case rules.

Never use these as ASCII art decorations:
- `===` or `----` (banner lines, section dividers)
- `[ok]` `[err]` `[skip]` (status tags — use `ok:` `err:` `skip:` prefix instead)
- `•` `|` `›` `‹` (bullet/separator characters in CLI text)

**Why:** Refines the prior dmesg/terse-voice rule. Lowercase-only feels sloppy in human-facing surfaces; ASCII decorations are visual noise the user explicitly disliked. Real dmesg uses lowercase because kernel space is constrained — MASTER isn't, so prose, CLI output, and commit subjects should read like written English. Commit-msg rule added 2026-05-07 after a lowercase commit subject slipped through.

**How to apply:**
- Comments: `# Restore HTML/CSS/typography sections` not `# restore html/css/typography sections`
- CLI output: `Wired /why to local lookup; LLM fallback only on miss.` not `[ok] /why now uses WhyExplainer first`
- Log lines: `Boot scan: 1678 violations (45s)` not `boot scan: 1678 violation(s)`
- Commit subjects: `Add foo`, `Fix bar`, `Refactor baz` — first word capitalized
- Section headers in YAML/code: drop `===== HEADER =====` style; use a single `#` line if needed
- Status indicators: `ok:` `err:` `warn:` as bare prefixes, never `[ok]`
- Bullet content in CLI: dash + space (`- item`) is fine; never use `•`

**Tension with dmesg style:** dmesg conventions apply ONLY to *kernel-style structured output emitted by MASTER itself* — the boot banner, event log lines, status pings (`master@host ready`, `boot0: 26ms`). The MASTER boot banner is explicitly sacred (user 2026-05-06: "dont remove boot message on startup, its awesome, and should remind of openbsd dmesg").

Do NOT use dmesg style for my own conversational prose to the user (clarified 2026-05-06: "dont use dmesg style for conversing prose"). When narrating progress in chat, write plain English sentences with proper casing. dmesg style is for log lines MASTER writes, not for me speaking to the operator.
