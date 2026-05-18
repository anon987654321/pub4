# Event naming convention

All bus events in MASTER follow `namespace:action` with snake_case. Read this before emitting a new event.

## Namespaces

| Namespace | Owner | When to use |
|---|---|---|
| `master:*` | core runtime | pipeline lifecycle, visual state, codebase-wide signals |
| `attention:*` | ground/now | attention context changes, breadcrumb updates |
| `judge:*` | judge | scan results, council start/done, violations |
| `trace:*` | trace | session records, telemetry, audit entries |
| `voice:*` | voice | TTS start/done, speech errors |

## Established events

```
master:visual          → visual_bridge.js topology/mode changes
master:clusters        → cluster registry updates
master:codebase        → repo-map or file-tree refreshes
master:rule_event      → scan rule fired
attention:context      → attention breadcrumb changed
judge:scan_start       → scan begun on a path
judge:scan_done        → scan results available
judge:council_start    → council deliberation opened
judge:council_done     → council result ready
sound_critique_start   → sound critique panel assembling (legacy — prefer judge:*)
sound_critique_done    → sound critique result ready (legacy — prefer judge:*)
```

## Rules

- Prefer `namespace:noun` over `namespace:verb_noun`. Use `attention:context` not `attention:context_changed`.
- `master:*` is for signals that cross subsystem boundaries. Subsystem-internal events use their own namespace.
- Never emit raw subsystem internals on `master:*`.
- JS listeners in `visual_bridge.js` normalize inbound events to `master:visual` before rendering — emit the raw event, let the bridge translate.
- New events must appear here before shipping.
