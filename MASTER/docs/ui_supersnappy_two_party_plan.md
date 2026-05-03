# UI: Two-Party Supersnappy Plan

Goals: explicit turn state, perceived latency under 120ms, two-channel output.

## Turn state machine

States: `idle` → `typing` → `sending` → `thinking` → `streaming` → `tool_running` → `awaiting_user` → `done` / `error`

Display current state at all times. Users must answer "whose turn is it?" in one glance.

## Output channels

Split assistant output into two channels:
- **Answer** — user-facing prose
- **Activity** — tools, events, progress (shown dim; collapse when done)

## Performance targets

- Submit → first visual feedback: < 120ms
- Submit → first token visible: < 900ms
- Stop action reaction: < 150ms perceived

Optimizations: instant echo user bubble, skeleton reservation, 16–32ms chunk flush cadence, optimistic markdown rendering.

## Web UI changes (priority order)

1. Explicit turn state indicator — always visible
2. Stop / Regenerate controls on active turn
3. Activity timeline under assistant bubble (collapsible)
4. Quick-reply chips for follow-up prompts
5. Focus mode: full-height chat, sticky composer, side panel for orb
6. Virtualized history for long sessions

## CLI changes

1. Per-turn latency row: `[thinking 420ms · first token 780ms · tools 2]`
2. Consistent keymap: Enter=send, Shift+Enter=newline, Tab=cycle suggestions, ↑=edit previous
3. Dim-prefixed activity lines: `· tool: read file…`

## Shared event schema

Both CLI and web emit: `turn.started`, `stream.delta`, `tool.started`, `tool.finished`, `turn.completed`, `turn.failed`

## Implementation phases

**Phase 1 (1–2 days):** Turn state machine, sending/thinking skeleton, stop control, timing instrumentation.

**Phase 2 (3–5 days):** Answer/activity channel split, chunk flush cadence, quick replies, CLI status row.

**Phase 3 (1 week):** Focus mode, virtualized history, shared event schema, server-side transcript persistence.
