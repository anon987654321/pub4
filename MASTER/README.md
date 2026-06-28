# MASTER

Constitutional AI runtime. Ruby. OpenBSD-first. Models propose; the constitution validates.

The web face (`web/`) mirrors internal state — council, pipeline stage, pressure. See `data/topologies.yml` and `web/public/particle_kernel.js`.

## Start

```sh
cd MASTER
bundle install
bundle exec ruby bin/cli
```

Web: port 53187, public at `https://ai.brgen.no`. Deploy: `DEPLOY/OPERATOR.md`.

Media: `/photograph`, `/video`, `/repligen` — `REPLICATE.md`, `bin/video help`.

## Pipeline

Eleven stages: Intake → Enhance → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render. Council and Lint run in parallel (30 s cap). Each stage returns `Result.ok(ctx)` or `Result.err(...)` and short-circuits on error.

## Modules

`now` · `loop` · `judge` · `voice` · `ground` · `reach` · `trace` · `converge`

Law in `data/`. Runtime state in `.master/`.

## Operating law

Agents do not mutate durable state directly. Tools declare contracts. Every action emits events. Rollback beats explanation.

Repair loop: observe → classify → propose → sandbox → validate → merge.

## Config

`.master/config.yml` — override at runtime with `/config key value`. Keys: `model`, `budget_max`, `req_max`, `reasoning_mode`, `auto`, `trace`, `cache_ttl`.

## Web auth

| Tier | Access |
|------|--------|
| Authenticated | Bearer / `X-Token` / `master_session` cookie — full tools |
| Visitor | LLM chat only |
| Public | `/up`, `/health` |

First `?token=…` sets an HttpOnly cookie and redirects without the query string.

## Philosophy

Not an autocomplete framework — a reviewer-sovereign runtime. Correctness before speed. Clarity before abstraction. Deletion before expansion. Full doctrine: `data/soul.yml`, `data/CANON.md`.

MIT.