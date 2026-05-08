---
name: Grok-inspired UI/CLI patterns (chatlog dump 2026-05-07)
description: Reference dump from a sister chat — StyleCoach UI prompt, htmx+SSE streaming, tty-prompt/tty-spinner advanced features, multi-line editor, character-stream LLM CLI. For MASTER's web UI and CLI polish.
type: reference
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
User shared a long Grok-style design conversation on 2026-05-07. Key reusable patterns:

## StyleCoach UI persona (LLM prompt)
Critique persona that evaluates MASTER's own output (CLI sessions, web partials, screenshots via vision).
Rules: *"interface should disappear; only the conversation should remain. Zero visual debt. Personality lives in words/spacing/timing, never in UI flourishes. Speed > everything. Mobile-first, dark-mode default. Every element earns its existence or it dies."*
Output format: `ELEMENT: ... / Current: ... / Suggested: ... / Reason: ...` and a final `distilled_ui_lesson` tag.
Distilled-rule examples: "If the user can see more than two accent colors, you have failed." "Spinners longer than three dots are crimes against humanity." "The prompt bar belongs at the bottom — always — like breathing."

## Streaming patterns (web UI)
- **htmx + SSE.** `<div hx-ext="sse" sse-connect="/stream/:id" sse-swap="chunk">`. Server writes `event: chunk\ndata: <span>...</span>\n\n` per token. Set `X-Accel-Buffering: no` for nginx/passenger. Sleep `rand(0.02..0.08)` for human-typing feel.
- **Chunked HTTP (no SSE ext).** `hx-trigger="load" hx-swap="innerHTML"`; server sets `Transfer-Encoding: chunked` and writes `CGI.escapeHTML(token)` per chunk. Zero extra JS.

## CLI polish — Grok-borrowable traits
1. Stream answers character-by-character via ANSI + `\r` overwrite of `Thinking…` line.
2. Terse happy path — no mandatory flags for 90% of cases.
3. Subtle personality on success and failure ("You had 7 nested conditionals. I removed them. You're welcome." / "Looks like you closed something you never opened.").
4. Stateful context across invocations without `--session` flag (tiny SQLite or `~/.master/context.json`).
5. Visual feedback >1.5s = braille spinner `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`. No emoji spinners, no rainbow bars.
6. One-command install + instant usefulness.

## tty-prompt advanced features (when MASTER CLI evolves)
- `select(filter: true)` — fuzzy-search list. `enum_select` — auto-complete predefined.
- `multi_select(per_page:, cycle:, symbols: { marker: "✔" })` — tag/category picking.
- `expand` — git-style `[(Y)es, (n)o, (a)ll, (q)uit]` compact menu.
- `editor("...", syntax: :markdown, word_wrap: 78, editor: ENV["EDITOR"])` — multi-line input via $EDITOR. Returns nil on cancel.
- `mask("API key:", required: true) { |q| q.confirm true }` — password input.
- `slider(min:, max:, step:, format:, active_color:)` — numeric tuning.
- `ask` validators: `q.in "18..120"`, `q.validate(/regex/)`, `q.convert :int`, `q.modify :strip, :downcase`.
- Theme: `TTY::Prompt.new(active_color: :bright_cyan, symbols: { marker: "❯", radio_on: "◉" })`.

## tty-spinner formats
Built-ins worth using: `:dots_8`, `:dots_9` (smooth braille — recommended default), `:spin`, `:simpleDotsScrolling`. Custom: `{ interval: 6, frames: %w[♥ ♡] }`. Multi-spinner: `TTY::Spinner::Multi.new` registers child spinners for parallel tasks. Always `hide_cursor: true`.

## Multi-line editor + Claude streaming (full example pattern)
`PROMPT.editor(...)` for multi-line, then `Anthropic::Client#messages.stream(stream: true) do |chunk|` → write `chunk.dig("delta","text")` char-by-char with `sleep(rand(0.008..0.035))`. Maintain `@history` array across turns. Spinner during pre-stream `Thinking…` then `.stop` before first byte.

## How to apply for MASTER
- MASTER's existing web UI (Rails 8 + Falcon, port 53187, two-tier auth) already streams via `POST /chat/message (SSE)`. Cross-check against the htmx+SSE pattern above.
- CLI REPL (`exe/master`) currently streams via `chunk_accumulator` + `print` — already char-stream-ish. Could borrow the `Thinking…` cleanup, the menu-on-ambiguity (`needs_clarification?`), and `tty-prompt editor` for the `<<` multiline mode.
- StyleCoach as a `/crit` persona variant is wired but could ingest screenshots via vision tool.

Don't bulk-import. Cherry-pick when a specific MASTER edit calls for it.
