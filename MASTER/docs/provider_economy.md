# Provider Economy

MASTER should treat providers as competing infrastructure.

The runtime selects providers by:

- capability
- latency
- hallucination rate
- timeout rate
- repair burden
- token cost
- context capacity
- historical reliability

## Principle

The orchestrator owns provider selection.

Models do not select themselves.

## Routing tiers

### Cheap cognition

Use inexpensive and fast providers for:

- classification
- compression
- retrieval ranking
- summarization
- critique
- voting
- lint reasoning

### Expensive cognition

Use expensive providers for:

- high-risk synthesis
- architecture decisions
- irreversible mutations
- council arbitration
- long-horizon planning

## Quarantine

Providers enter quarantine when:

- hallucination rate spikes
- retries exceed threshold
- invalid structured outputs repeat
- timeout rate climbs
- corruption incidents increase

## Long-term direction

Provider routing becomes:

```text
workflow
  -> capability routing
  -> health scoring
  -> quorum
  -> replay analysis
  -> repair feedback
  -> adaptive optimization
```

The provider layer becomes a runtime economy, not a static config file.
