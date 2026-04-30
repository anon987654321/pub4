# MASTER UI Improvement Plan: Repl/CLI + Rails Web

## Goals

1. Make two-party communication explicit and low-friction (You ↔ MASTER).
2. Reduce perceived latency to "instant" with progressive feedback.
3. Keep current personality/aesthetic while improving readability and control.

---

## Current Baseline (from code)

- Rails chat UI already streams assistant output from `POST /chat/message` and appends chunks in-place.
- Chat history is persisted in `localStorage` and replayed at load.
- Status text changes during streaming/tool events.
- The main web UI has a strong visual/audio layer, with chat log as a secondary panel.

This is a good foundation for a "supersnappy" experience, but there are opportunities to tighten interaction loops and clarify two-party turn state.

---

## 1) Two-Party Communication Model (core UX)

### A. Turn contract: one visible state machine

Introduce a shared turn model for both CLI and Web:

- `idle`
- `recording` / `typing`
- `sending`
- `thinking` (first-token pending)
- `streaming`
- `tool_running`
- `awaiting_user` (assistant asks follow-up)
- `done`
- `error`

**Why:** users trust the system more when they can always answer: "whose turn is it and what is happening?"

### B. Message anatomy for both parties

Render each turn with standardized metadata:

- speaker (`you` / `master`)
- timestamp
- latency markers (`sent`, `first token`, `completed`)
- optional tool summary row (collapsed by default)

### C. Hard separation of channels

Split assistant output into two channels:

1. **Answer channel** (user-facing prose)
2. **Activity channel** (tools/events/progress)

In web: activity shows as subtle timeline under composing assistant bubble.
In CLI: activity appears as dim prefixed lines (e.g., `· tool: read file…`).

### D. Explicit follow-up prompts

When MASTER needs more input, show **quick replies** (chips/buttons in web; numbered choices in CLI).
This dramatically reduces back-and-forth friction and keeps momentum.

---

## 2) "Supersnappy" Feel (perceived performance)

### A. First-feedback under 120ms

On submit:

- instantly echo user bubble
- animate "sending" indicator
- reserve assistant bubble skeleton immediately

Target: user always sees reaction in <120ms even before network returns.

### B. First-token optimization budget

Track and optimize three metrics:

- input submit → request start
- request start → first token
- first token → final token

Display only a friendly abstraction in UI (e.g., "Connected", "Thinking", "Writing"), but log exact timings for tuning.

### C. Stream cadence smoothing

If chunks are bursty, buffer for 16–32ms and flush on animation frames.
Result: smoother reading and less "stutter" without meaningful delay.

### D. Optimistic markdown rendering

Render incrementally with lightweight parser rules during stream; re-render final block at completion for correctness.

### E. Progressive disclosure of heavy work

For tool use or long reasoning tasks:

- show short step labels early ("Scanning project", "Drafting fix")
- keep technical details collapsible

This preserves speed perception while retaining transparency.

---

## 3) Repl/CLI-specific recommendations

### A. Split-pane terminal mode

Offer optional TUI mode:

- upper pane: conversation
- lower pane: input composer
- side/right mini-pane: activity/tool events

Fallback to plain line mode when terminal lacks support.

### B. Deterministic keyboard flow

- `Enter`: send
- `Shift+Enter`: newline
- `Ctrl+L`: clear viewport only
- `Tab`: cycle suggested replies/commands
- `↑`: edit previous prompt

### C. Streaming typography

- avoid reflow jumps by fixed wrapping width per turn
- color roles consistently
- show cursor/typing glyph only at active stream tail

### D. Latency affordances

CLI status row example:

`[thinking 420ms · first token 780ms · tools 2]`

Power users love this; it signals responsiveness honestly.

---

## 4) Rails Web UI-specific recommendations

### A. Promote chat log to first-class surface

Current overlay-style log is cool, but for sustained two-party chat add a "focus mode":

- full-height conversation view
- sticky composer
- optional side panel for visuals/orb

### B. Sticky composer with intent helpers

Add small controls beside input:

- tone/mode selector ("brief", "deep", "code")
- attach context shortcut
- quick actions: "summarize", "plan", "next step"

### C. Activity timeline under assistant bubble

Show tiny inline progress events during stream:

- Connected
- Reading files
- Drafting response
- Finalizing

Collapse automatically when done.

### D. Better interruption model

Add **Stop** and **Regenerate** controls directly on active turn.
Interruptibility is a core component of "fast" feeling.

### E. Virtualized long history

For long sessions, virtualize DOM list to avoid frame drops and memory bloat; keep scroll anchoring stable during stream.

### F. Network resilience cues

When disconnected/slow:

- explicit banner with retry state
- queued message indicator
- no silent failures

---

## 5) Architecture improvements that unlock UX speed

### A. Unified event schema (CLI + Web)

Emit shared structured events:

- `turn.started`
- `stream.delta`
- `tool.started`
- `tool.finished`
- `turn.completed`
- `turn.failed`

Both clients consume same semantics, reducing divergence.

### B. Session transcript service

Persist canonical transcript server-side (not only `localStorage`):

- enables cross-device continuity
- safer recovery
- easier analytics for latency and drop-off

### C. Token + tool telemetry

Store anonymized per-turn performance stats and outcome quality signals.
Use this to rank improvements by impact, not guesswork.

---

## 6) Implementation roadmap (practical)

### Phase 1 (1–2 days)

- Add explicit turn state machine in UI layer
- Add first-feedback skeleton + sending/thinking labels
- Add stop/regenerate controls
- Add timing instrumentation (submit/first-token/done)

### Phase 2 (3–5 days)

- Introduce answer vs activity channel separation
- Implement smooth chunk flush cadence
- Add quick replies for follow-up prompts
- Add CLI status row and consistent keymap

### Phase 3 (1 week)

- Focus mode for web chat
- Virtualized history
- Shared event schema across CLI/web
- Session transcript backend persistence

---

## 7) "Definition of supersnappy" (success criteria)

- P50 submit→first visual feedback: <120ms
- P50 submit→first token visible: <900ms
- P95 stream frame drops: near-zero on typical laptop/mobile
- User can always identify current turn state in one glance
- Interrupt (Stop) action reacts in <150ms perceived time

---

## 8) High-impact quick wins (do these first)

1. Immediate assistant skeleton + "thinking" state.
2. Stop button during streaming.
3. Activity events rendered as subtle inline timeline.
4. Quick-reply chips for clarifying questions.
5. Simple per-turn latency telemetry dashboard.

These five changes usually produce the biggest jump in perceived speed and quality of two-party flow.
