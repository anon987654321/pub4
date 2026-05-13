# Telemetry Runtime

Telemetry is append-only unless explicitly compacted.

Files:

- failures.ndjson
- hallucinations.ndjson
- corrections.ndjson
- retries.ndjson
- provider_latency.ndjson
- token_usage.ndjson
- context_pressure.ndjson
- tool_calls.ndjson

Every line is a standalone JSON object with:

- timestamp
- workflow_id
- provider
- model
- subsystem
- severity
- tags
- payload

Telemetry feeds:

- provider scoring
- repair daemons
- hallucination clustering
- retry heuristics
- context compaction
- drift analysis
- routing optimization
