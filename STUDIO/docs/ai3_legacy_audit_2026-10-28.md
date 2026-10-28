# AI3 legacy-lineage audit — 2026-10-28

## Decision

Treat the historical AI3 tree as a source of requirements and provenance, not as a verified implementation to transplant into pub4. This audit found no AI3 component whose implementation quality justifies a wholesale port on the evidence currently available.

This is a bounded audit, not a claim of exhaustive archive recovery. The visible `ai3/` tree and extracted historical reports were inspected; 97 unique historical archive blobs (about 162 MB compressed in aggregate) were not all extracted and audited byte-for-byte in this environment. No AI3 or pub4 tests were run as part of this note.

## Findings with direct source references

- [AI3 implementation summary](https://github.com/anon987654321/pub/blob/main/__OLD_BACKUPS/ai33/AI3_IMPLEMENTATION_SUMMARY.md) calls task execution a placeholder, says only three assistants are fully implemented, and describes the wider set as configured or base implementations.
- [Migration report](https://github.com/anon987654321/pub/blob/main/__OLD_BACKUPS/ai33/MIGRATION_REPORT.md) acknowledges mock/stub integrations and pre-existing syntax/dependency issues despite a broad migration-complete claim.
- [Weaviate integration](https://github.com/anon987654321/pub/blob/main/ai3/lib/weaviate_integration.rb) does not demonstrate a live vector-store integration: indexing checks return a fixed negative result and adding data prints a message / returns mock output.
- [Musicians assistant](https://github.com/anon987654321/pub/blob/main/ai3/assistants/musicians.rb) describes multiple genre agents and data sources, but its platform scrapers return empty collections, the apparent parallel orchestration iterates sequentially, and publishing is simulated with fabricated content identifiers.
- AI3's [assistant specs](https://github.com/anon987654321/pub/tree/main/ai3/spec/assistants) contain generic response-smoke assertions rather than tests proving the advertised integrations.
- Additional inspected modules contain console-message-only mastering operations, placeholder audio effects, hard-coded material-science embeddings, and a Linux/OpenBSD translation path with a dummy checksum / simulated download. These are not suitable to port as working capability.

## What this evidence does and does not establish

The source shows useful *intent*: capability-oriented assistant registration, specialist configuration, orchestration, session continuity, caching and user preference adaptation. It does not prove those features were reliable or production-connected. Similar concepts may already have authoritative implementations in pub4; this report deliberately does not prescribe duplicate code or propose edits to `MASTER`.

The [pub4 MASTER contributor contract](https://github.com/anon987654321/pub4/blob/main/MASTER/AGENTS.md) requires the full `MASTER/` tree to be read before planning or editing it. That gate has **not** been satisfied by this audit. Consequently, no MASTER source changes are authorized by this note. Any future comparison must first satisfy that gate, then prove a concrete behavior against the current owner and regression tests; it must not copy AI3's declared feature list as evidence of working behavior.

## Evidence status

- Source inspection: **PARTIAL** — visible AI3 files and extracted reports.
- Historical archive recovery: **INCOMPLETE** — not all archive blobs extracted.
- Runtime / integration tests: **NOT_RUN**.
- Port authorization: **NONE** based on this audit alone.
