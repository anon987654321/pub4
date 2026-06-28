---
name: Grok-inspired UI/CLI patterns (chatlog dump 2026-05-07)
description: Reference dump from a sister chat — StyleCoach UI prompt, htmx+SSE streaming, tty-prompt/tty-spinner advanced features, multi-line editor, character-stream LLM CLI. For MASTER's web UI and CLI polish.
type: reference
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---

This is a Grok-style design dump from 2026-05-07. Cherry-pick ideas; do not bulk-import.

StyleCoach critiques MASTER output across CLI, web, and screenshots. Rules: the interface disappears; zero visual debt; personality lives in words, spacing, and timing; speed beats everything; mobile-first dark; every element must earn its place. Format is `ELEMENT/Current/Suggested/Reason` plus `distilled_ui_lesson`. Examples include at most two accent colors, spinners of at most three dots, and a prompt bar fixed at the bottom.

Web streaming uses htmx+SSE with `sse-connect="/stream/:id"` and `event: chunk`, plus `X-Accel-Buffering: no` and sleep `rand(0.02..0.08)`. Alternatively use chunked HTTP with `hx-swap="innerHTML"`.

CLI traits favor char-stream via ANSI `\r` over `Thinking…`, a terse happy path, subtle personality on success and failure, stateful context in SQLite or `~/.master/context.json`, a braille spinner `⠋⠙⠹…` after 1.5s, and one-command install.

tty-prompt offers `select(filter:)`, `multi_select`, `expand`, `editor(syntax:, word_wrap:)`, `mask`, `slider`, and validators (`in`, `validate`, `convert`, `modify`). Theme uses bright_cyan with `❯` and `◉`. tty-spinner defaults to `:dots_9`, supports `Multi` for parallel work, and uses `hide_cursor: true`. Multi-line input uses `PROMPT.editor` with Anthropic stream char-by-char at `sleep(rand(0.008..0.035))`.

MASTER already streams SSE on `POST /chat/message` and CLI via `chunk_accumulator`. Borrow Thinking cleanup, ambiguity menus, and tty `editor` for `<<` mode. StyleCoach fits as `/crit` plus a vision tool.