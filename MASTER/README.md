# MASTER

Constitutional AI runtime in Ruby, OpenBSD-first. Models propose; the constitution validates before durable writes. The web face in `web/` mirrors pipeline state at `https://ai.brgen.no`.

Local boot: `bundle install`, then `bundle exec ruby bin/cli`. Pipeline stages are in `Now::RuntimeMode::PIPELINE_STAGES`; dump with `/orient`. Law is `data/soul.yml` and `data/rules.yml`. Deploy: `DEPLOY/OPERATOR.md`. Licensed MIT.

Start with `START_HERE.md`; use `EXAMPLES.md` when in doubt about patch shape. Use `bin/check` for ordinary contributor validation, `bin/check --profile=agent` for law/agent changes, `bin/check --profile=web` for the face, and `bin/check --profile=full` for operator-grade gates.

Two spines share the `Master::` namespace intentionally. `lib/` is the application/runtime spine loaded by the gem and the CLI. `core/` is a small constitutional fold spine (`Master::Core::`) loaded on its own path by `bin/master-core` and the core tests. Because it lives under `Master::Core::` (not top-level `Master::`), it coexists with `lib/` in one process without constant collisions.
