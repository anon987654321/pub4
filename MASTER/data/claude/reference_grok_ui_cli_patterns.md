---
name: Grok-inspired UI/CLI patterns (chatlog dump 2026-05-07)
description: Reference dump from a sister chat — StyleCoach UI prompt, htmx+SSE streaming, tty-prompt/tty-spinner advanced features, multi-line editor, character-stream LLM CLI. For MASTER's web UI and CLI polish.
type: reference
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
Grok-style design dump 2026-05-07. Cherry-pick; don't bulk-import.

**StyleCoach persona:** critique MASTER output (CLI, web, screenshots). Rules: interface disappears; zero visual debt; personality in words/spacing/timing; speed > all; mobile-first dark; every element earns existence. Format: `ELEMENT/Current/Suggested/Reason` + `distilled_ui_lesson`. Examples: ≤2 accent colors; spinners ≤3 dots; prompt bar bottom always.

**Web streaming:** htmx+SSE `sse-connect="/stream/:id"` + `event: chunk`; `X-Accel-Buffering: no`; sleep `rand(0.02..0.08)`. Or chunked HTTP + `hx-swap="innerHTML"`.

**CLI traits:** char-stream via ANSI `\r` over `Thinking…`; terse happy path; subtle personality on success/fail; stateful context (SQLite/`~/.master/context.json`); braille spinner `⠋⠙⠹…` after 1.5s; one-command install.

**tty-prompt:** `select(filter:)`, `multi_select`, `expand`, `editor(syntax:, word_wrap:)`, `mask`, `slider`, validators (`in`, `validate`, `convert`, `modify`). Theme: bright_cyan + `❯`/`◉`.

**tty-spinner:** `:dots_9` default; `Multi` for parallel; `hide_cursor: true`. Multi-line: `PROMPT.editor` → Anthropic stream char-by-char `sleep(rand(0.008..0.035))`.

**MASTER fit:** web already SSE on `POST /chat/message`; CLI streams via `chunk_accumulator`. Borrow Thinking cleanup, ambiguity menus, tty `editor` for `<<` mode. StyleCoach `/crit` + vision tool.