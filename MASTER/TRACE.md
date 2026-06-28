# Trace map

MASTER records what happened through a live event bus and durable on-disk ledgers so operators can triage without guessing.

`Trace::EventBus` carries pipeline stages, tools, and scans. On the CLI, `/tail 20 pipeline` shows recent pipeline events; on the web, `/events/stream` streams them.

Activity lands in `runtime/events/activity.jsonl` and is read with `/tail` or `/replay`. Evidence is stored under `runtime/evidence/` and replayed with `/replay evidence`. Session state is in `.master/session.yml` via `/history`. Undo snapshots live in `.master/undo/` and are restored with `/undo`.

For triage, `/status` gives a health snapshot, `/tail` or `/dmesg` shows recent events, and `bin/probe` checks readiness without a browser. Key event types include `pipeline:stage_start`, `review:verdict`, `scan:progress`, and `route:resolved`.