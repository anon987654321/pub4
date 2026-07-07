# MASTER

Constitutional AI runtime in Ruby, OpenBSD-first. Models propose; the constitution validates before durable writes. The web face in `web/` mirrors pipeline state at `https://ai.brgen.no`.

Local boot: `bundle install`, then `bundle exec ruby bin/cli`. Pipeline stages are in `Now::RuntimeMode::PIPELINE_STAGES`; dump with `/orient`. Law is `data/soul.yml` and `data/rules.yml`. Deploy: `DEPLOY/OPERATOR.md`. Media: `/orient replicate` or `bin/video help`. Licensed MIT.

Start with `START_HERE.md`; use `EXAMPLES.md` when in doubt about patch shape. Use `bin/check` for ordinary contributor validation, `bin/check-agent` for law/agent changes, `bin/check-web` for the face, and `bin/check-full` for operator-grade gates.

Two spines share the `Master::` namespace intentionally. `lib/` is the application/runtime spine loaded by the gem and the CLI. `kernel/` is a small constitutional fold spine loaded on its own path by `bin/master-kernel` and kernel tests. Namespace audits skip the kernel entrypoint so the two-spine design is not mistaken for accidental duplicate constants.
