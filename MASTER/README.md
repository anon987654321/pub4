# MASTER

MASTER is a constitutional AI runtime written in Ruby and designed OpenBSD-first. Models propose changes; the constitution validates them before anything durable is written. The web face in `web/` mirrors internal state—council deliberation, pipeline stage, and system pressure—so operators can see what the runtime is doing without opening a shell. Topology and the particle kernel are documented in `data/topologies.yml` and implemented in `web/public/particle_kernel.js`.

To work locally, change into `MASTER`, run `bundle install`, and start the CLI with `bundle exec ruby bin/cli`. The web tier listens on port 53187 and is publicly served at `https://ai.brgen.no`. Deployment, SSH, and relayd details live in `DEPLOY/OPERATOR.md`. Media generation uses `/photograph`, `/video`, and `/repligen`; see `REPLICATE.md` and `bin/video help` for model and workflow specifics.

The pipeline has eleven stages: Intake, Enhance, Infer, Route, Guard, Execute, then Council and Lint in parallel under a thirty-second cap, followed by Prune, Memo, and Render. Each stage returns `Result.ok(ctx)` or `Result.err(...)` and short-circuits on error. The codebase is organized into modules—`now`, `loop`, `judge`, `voice`, `ground`, `reach`, `trace`, and `converge`—with law in `data/` and runtime state under `.master/`.

Agents do not mutate durable state directly. Tools declare contracts, every action emits events, and rollback beats explanation. The repair loop is observe, classify, propose, sandbox, validate, merge. Runtime overrides go through `.master/config.yml` or `/config key value` for keys such as `model`, `budget_max`, `req_max`, `reasoning_mode`, `auto`, `trace`, and `cache_ttl`.

Web authentication has three tiers. Authenticated callers use Bearer tokens, `X-Token`, or a `master_session` cookie and receive full tool access. Visitors get LLM chat only. Public endpoints include `/up` and `/health`. The first request with `?token=…` sets an HttpOnly cookie and redirects without the query string.

MASTER is not an autocomplete framework—it is a reviewer-sovereign runtime. Correctness comes before speed, clarity before abstraction, and deletion before expansion. Full doctrine is in `data/soul.yml` and `data/CANON.md`. Licensed MIT.