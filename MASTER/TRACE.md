# Trace map

## Live bus

`Trace::EventBus` — pipeline stages, tools, scans. CLI: `/tail 20 pipeline`. Web: `/events/stream`.

## Disk

| Ledger | Path | Command |
|--------|------|---------|
| Activity | `runtime/events/activity.jsonl` | `/tail`, `/replay` |
| Evidence | `runtime/evidence/` | `/replay evidence` |
| Session | `.master/session.yml` | `/history` |
| Undo | `.master/undo/` | `/undo` |

## Triage

1. `/status` — health snapshot
2. `/tail` or `/dmesg` — recent events
3. `bin/probe` — readiness without browser

Key events: `pipeline:stage_start`, `review:verdict`, `scan:progress`, `route:resolved`.