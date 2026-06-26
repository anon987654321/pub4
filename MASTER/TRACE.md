# MASTER trace map

Where operational truth lives and which command to use.

## Live bus (in-process)

`Trace::EventBus` — every pipeline stage, tool call, scan, and loop publishes here. Subscribe with `bus.subscribe("pattern")` or `bus.subscribe("*")`.

CLI: `/tail 20 pipeline` · Web: `/events/stream` SSE · Face: `topology_registry.js`

## On-disk ledgers

| Ledger | Path | Use when |
|--------|------|----------|
| Activity | `runtime/events/activity.jsonl` | General incident triage — `/tail`, `/replay` |
| Evidence | `runtime/evidence/` | Proof-backed decisions — `/replay evidence` |
| Feedback | via `FeedbackLedger` | Self-improvement patterns — `/analyze-self` |
| Reflexion | via `ReflexionLedger` | Retry/learn loops |
| Swallow | boot-time silent rescues | `/swallow-report` |
| Session | `.master/session.yml` | Turn history — `/history` |
| Undo | `.master/undo/` | File rollback — `/undo` |

## Operator triad

1. `/status` — one-frame health (git, loops, last pipeline stage, review verdict)
2. `/tail` or `/dmesg` — recent bus-backed lines
3. `bin/probe` — readiness without Chrome

## Key events

| Event | Meaning |
|-------|---------|
| `pipeline:stage_start` / `complete` | Turn progress |
| `review:verdict` | Lint + council score (non-blocking) |
| `scan:progress` | Deep scan ETA (`done/total`) |
| `route:resolved` | Slash vs NL routing |
| `cli:violation_delta` | Background scan delta |

## Web trace

First SSE frame includes `trace_id` (chat + events stream). Set `document.documentElement.dataset.trace` for support.