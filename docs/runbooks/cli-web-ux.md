# Runbook: CLI and web interaction reliability

This runbook covers behavior that otherwise looks like “the system is slow”
or “the UI accepted it” even when nothing happened. Run the relevant source
regressions first, then verify the actual CLI and browser surfaces. Keep the
root TODO.md as the only queue.

## Latency and acknowledgement

Measure with a monotonic clock and the same pinned commit. Record cold boot,
warm boot, input acknowledgement, first visible token, completed reply and
greeting separately, including selected model/provider, retries and fallback
hops. The proposed acceptance targets are input acknowledgement <=100 ms,
first token <=2 s, greeting <=3 s and --help/--version/--status <=200 ms.
These are goals to measure against; do not claim they are met until observed
on the target hardware. Confirm fast-path flags avoid full runtime boot.

On Enter, show immediate input echo or a real pending state. Progress must be
observable and truthful; no response for many seconds must not look identical
to a disconnected or dead process.

## CLI cancellation and terminal state

Exercise Ctrl-C during generation, Ctrl-D at the prompt, SIGTERM and a child
process timeout. Define and verify what happens to partial output, child
processes, terminal raw mode, bracketed paste and alternate-screen state.
After every exit/error path the prompt or shell must be usable again. Verify
NO_COLOR, TERM=dumb, non-TTY piping and that the face is suppressed in
dumb/non-interactive terminals. A resize must preserve the prompt and usable
scrollback. Long replies need history/search or an explicit bounded display
with a truthful “more output” affordance, not silent truncation.

## Browser connection and message lifecycle

For WebSocket drop, reconnect, server error and offline mid-reply, verify
visible connected/reconnecting/offline state and a meaningful retry outcome.
Every outgoing message has a visible pending -> sent/delivered -> failed/retry
lifecycle grounded in what the server actually confirmed. A successful local
enqueue is not proof of delivery.

Double-Enter, reload, network retry and reconnect must not duplicate a send.
Use server-backed idempotency keys or the actual contract already in the
application; do not rely on a disabled button alone. Reload mid-conversation
and verify history, scroll position and unsent draft survive safely. Do not
resend a draft merely because the browser reloaded.

## Keyboard, narrow widths and motion

Test keyboard-only use, visible focus, Escape semantics, an accessible shortcut
help surface, and absence of focus traps. At narrow widths and with a mobile
keyboard open, the prompt stays visible above the safe area. Honor
prefers-reduced-motion for cursor blink, streamed rendering and the animated
face. Forced-colors mode must retain visible focus and status information.

## Honest affordances

Never imply a reminder will alert unless a real delivery channel is configured
and scheduled. State timezone and delivery capability at acceptance time.
Ordinary factual lookup must follow the approved search policy; a question
asking for an opinion must not trigger unrelated web searches. Scope-changing
actions require confirmation. Capability descriptions must match live
capabilities, not repository features or adapters that have not been exercised.

Capture one artifact per meaningful scenario and attach screenshots, CLI logs,
server-side event/status evidence and the exact commit. A static contract does
not prove a user-perceived state transition.
