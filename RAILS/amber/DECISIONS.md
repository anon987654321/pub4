# Amber decisions

Intentional shapes that may otherwise look like bugs. Same purpose as
`MASTER/DECISIONS.md`. Components: `ARCHITECTURE.md`.

## Embedding vectors are JSON, not pgvector

`GarmentEmbedding#vector` is a JSON column (`db/schema.rb:184`, `t.json
"vector"`) so Amber stays SQLite-compatible (`config/database.yml`, `adapter:
sqlite3`). `pgvector` is referenced in `app/jobs/fingerprint_garment_job.rb` and
`app/services/wardrobe_ai.rb` but not migrated to.

Moving to PostgreSQL means replacing the JSON column with a pgvector column and
swapping `WardrobeAi#embedding_for` for a real embedding backend. `apps.yml`
lists PostgreSQL/pgvector under `stack_later`; the horizon entry is `agent:
ignore`.

A JSON column holding vectors looks like something to fix. It is a choice made
to keep one database engine across all three apps on a 1GB VPS. This rationale
lived only in `DEPLOY/rails/amber/ARCHITECTURE.md` and disappeared with it at
`ee3a56e33` (2026-08-03 audit).

## `Item` and `WardrobeItem` are both correct

`WardrobeItem belongs_to :item` with a uniqueness scope on `[user_id, item_id]`
and carries condition alone. It is the per-owner care record on a garment, not a
second garment model. Merging them loses the distinction between what a garment
is and what one owner's copy is worth wearing.
